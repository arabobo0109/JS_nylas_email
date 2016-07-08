const {
  SchedulerUtils,
  IMAPConnection,
  PubsubConnector,
  DatabaseConnector,
  MessageTypes,
} = require('nylas-core');
const {
  jsonError,
} = require('./sync-utils')

const {CLAIM_DURATION} = SchedulerUtils;

const FetchFolderList = require('./imap/fetch-category-list')
const FetchMessagesInFolder = require('./imap/fetch-messages-in-category')
const SyncbackTaskFactory = require('./syncback-task-factory')


class SyncWorker {
  constructor(account, db, onExpired) {
    this._db = db;
    this._conn = null;
    this._account = account;
    this._startTime = Date.now();
    this._lastSyncTime = null;
    this._onExpired = onExpired;

    this._syncTimer = null;
    this._expirationTimer = null;
    this._destroyed = false;

    this.syncNow({reason: 'Initial'});

    this._onMessage = this._onMessage.bind(this);
    this._listener = PubsubConnector.observeAccount(account.id).subscribe(this._onMessage)
  }

  cleanup() {
    this._destroyed = true;
    this._listener.dispose();
    this.closeConnection()
  }

  closeConnection() {
    if (this._conn) {
      this._conn.end();
    }
    this._conn = null
  }

  _onMessage(msg) {
    const {type} = JSON.parse(msg);
    switch (type) {
      case MessageTypes.ACCOUNT_UPDATED:
        this._onAccountUpdated(); break;
      case MessageTypes.SYNCBACK_REQUESTED:
        this.syncNow({reason: 'Syncback Action Queued'}); break;
      default:
        throw new Error(`Invalid message: ${msg}`)
    }
  }

  _onAccountUpdated() {
    if (this.isNextSyncScheduled()) {
      this._getAccount().then((account) => {
        this._account = account;
        this.syncNow({reason: 'Account Modification'});
      });
    }
  }

  _onConnectionIdleUpdate() {
    this.syncNow({reason: 'IMAP IDLE Fired'});
  }

  _getAccount() {
    return DatabaseConnector.forShared().then(({Account}) =>
      Account.find({where: {id: this._account.id}})
    );
  }

  _getIdleFolder() {
    return this._db.Folder.find({where: {role: ['all', 'inbox']}})
  }

  ensureConnection() {
    if (this._conn) {
      return this._conn.connect();
    }
    const settings = this._account.connectionSettings;
    const credentials = this._account.decryptedCredentials();

    if (!settings || !settings.imap_host) {
      return Promise.reject(new Error("ensureConnection: There are no IMAP connection settings for this account."))
    }
    if (!credentials) {
      return Promise.reject(new Error("ensureConnection: There are no IMAP connection credentials for this account."))
    }

    const conn = new IMAPConnection(this._db, Object.assign({}, settings, credentials));
    conn.on('mail', () => {
      this._onConnectionIdleUpdate();
    })
    conn.on('update', () => {
      this._onConnectionIdleUpdate();
    })
    conn.on('queue-empty', () => {
    });

    this._conn = conn;
    return this._conn.connect();
  }

  syncbackMessageActions() {
    const where = {where: {status: "NEW"}, limit: 100};
    return this._db.SyncbackRequest.findAll(where)
      .map((req) => SyncbackTaskFactory.create(this._account, req))
      .each(this.runSyncbackTask.bind(this))
  }

  runSyncbackTask(task) {
    const syncbackRequest = task.syncbackRequestObject()
    return this._conn.runOperation(task)
    .then(() => {
      syncbackRequest.status = "SUCCEEDED"
    })
    .catch((error) => {
      syncbackRequest.error = error
      syncbackRequest.status = "FAILED"
    }).finally(() => syncbackRequest.save())
  }

  syncAllCategories() {
    const {Folder} = this._db;
    const {folderSyncOptions} = this._account.syncPolicy;

    return Folder.findAll().then((categories) => {
      const priority = ['inbox', 'all', 'drafts', 'sent', 'spam', 'trash'].reverse();
      const categoriesToSync = categories.sort((a, b) =>
        (priority.indexOf(a.role) - priority.indexOf(b.role)) * -1
      )

      return Promise.all(categoriesToSync.map((cat) =>
        this._conn.runOperation(new FetchMessagesInFolder(cat, folderSyncOptions))
      ))
    });
  }

  performSync() {
    return this.syncbackMessageActions()
    .then(() => this._conn.runOperation(new FetchFolderList(this._account.provider)))
    .then(() => this.syncAllCategories())
  }

  syncNow({reason} = {}) {
    clearTimeout(this._syncTimer);
    this._syncTimer = null;

    if (!process.env.SYNC_AFTER_ERRORS && this._account.errored()) {
      console.log(`SyncWorker: Account ${this._account.emailAddress} (${this._account.id}) is in error state - Skipping sync`)
      return
    }
    console.log(`SyncWorker: Account ${this._account.emailAddress} (${this._account.id}) sync started (${reason})`)

    this.ensureConnection()
    .then(() => this._account.update({syncError: null}))
    .then(() => this.performSync())
    .then(() => this.onSyncDidComplete())
    .catch((error) => this.onSyncError(error))
    .finally(() => {
      this._lastSyncTime = Date.now()
      this.scheduleNextSync()
    })
  }

  onSyncError(error) {
    console.error(`SyncWorker: Error while syncing account ${this._account.emailAddress} (${this._account.id})`, error)
    this.closeConnection()

    if (error.source === 'socket') {
      // Continue to retry if it was a network error
      return Promise.resolve()
    }
    this._account.syncError = jsonError(error)
    return this._account.save()
  }

  onSyncDidComplete() {
    const {afterSync} = this._account.syncPolicy;

    if (!this._account.firstSyncCompletedAt) {
      this._account.firstSyncCompletedAt = Date.now()
    }

    const now = Date.now();
    const syncGraphTimeLength = 60 * 30; // 30 minutes, should be the same as SyncGraph.config.timeLength
    let lastSyncCompletions = [...this._account.lastSyncCompletions]
    lastSyncCompletions = [now, ...lastSyncCompletions]
    while (now - lastSyncCompletions[lastSyncCompletions.length - 1] > 1000 * syncGraphTimeLength) {
      lastSyncCompletions.pop();
    }

    this._account.lastSyncCompletions = lastSyncCompletions
    this._account.save()
    console.log('Syncworker: Completed sync cycle')

    if (afterSync === 'idle') {
      return this._getIdleFolder()
      .then((idleFolder) => this._conn.openBox(idleFolder.name))
      .then(() => console.log('SyncWorker: - Idling on inbox category'))
    }

    if (afterSync === 'close') {
      console.log('SyncWorker: - Closing connection');
      this.closeConnection()
      return Promise.resolve()
    }

    throw new Error(`SyncWorker.onSyncDidComplete: Unknown afterSync behavior: ${afterSync}. Closing connection`)
  }

  isNextSyncScheduled() {
    return this._syncTimer != null;
  }

  scheduleNextSync() {
    if (Date.now() - this._startTime > CLAIM_DURATION) {
      console.log("SyncWorker: - Has held account for more than CLAIM_DURATION, returning to pool.");
      this.cleanup();
      this._onExpired();
      return;
    }

    SchedulerUtils.checkIfAccountIsActive(this._account.id).then((active) => {
      const {intervals} = this._account.syncPolicy;
      const interval = active ? intervals.active : intervals.inactive;

      if (interval) {
        const target = this._lastSyncTime + interval;
        console.log(`SyncWorker: Account ${active ? 'active' : 'inactive'}. Next sync scheduled for ${new Date(target).toLocaleString()}`);
        this._syncTimer = setTimeout(() => {
          this.syncNow({reason: 'Scheduled'});
        }, target - Date.now());
      }
    });
  }
}

module.exports = SyncWorker;
