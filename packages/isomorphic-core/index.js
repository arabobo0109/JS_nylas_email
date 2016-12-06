/* eslint global-require: 0 */
module.exports = {
  Provider: {
    Gmail: 'gmail',
    IMAP: 'imap',
  },
  Imap: require('imap'),
  IMAPErrors: require('./src/imap-errors'),
  loadModels: require('./src/load-models'),
  AuthHelpers: require('./src/auth-helpers'),
  PromiseUtils: require('./src/promise-utils'),
  DatabaseTypes: require('./src/database-types'),
  IMAPConnection: require('./src/imap-connection'),
  DeltaStreamBuilder: require('./src/delta-stream-builder'),
  HookTransactionLog: require('./src/hook-transaction-log'),
  HookIncrementVersionOnSave: require('./src/hook-increment-version-on-save'),
}
