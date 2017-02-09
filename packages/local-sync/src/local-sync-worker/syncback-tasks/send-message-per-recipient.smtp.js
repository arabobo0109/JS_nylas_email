const {SendmailClient, Errors: {APIError}} = require('isomorphic-core')
const Utils = require('../../shared/utils')
const SyncbackTask = require('./syncback-task')
const MessageFactory = require('../../shared/message-factory')


async function sendPerRecipient({db, account, baseMessage, usesOpenTracking, usesLinkTracking, logger = console} = {}) {
  const {Message} = db
  const recipients = baseMessage.getRecipients()
  const failedRecipients = []

  for (const recipient of recipients) {
    const customBody = MessageFactory.buildTrackingBodyForRecipient({
      recipient,
      baseMessage,
      usesOpenTracking,
      usesLinkTracking,
    })

    const individualizedMessage = Utils.copyModel(Message, baseMessage, {
      body: customBody,
    })
    // TODO we set these temporary properties which aren't stored in the
    // database model because SendmailClient requires them to send the message
    // with the correct headers.
    // This should be cleaned up
    individualizedMessage.references = baseMessage.references;
    individualizedMessage.inReplyTo = baseMessage.inReplyTo;

    try {
      const sender = new SendmailClient(account, logger);
      await sender.sendCustom(individualizedMessage, {to: [recipient]})
    } catch (error) {
      logger.error(error, {recipient: recipient.email}, 'SendMessagePerRecipient: Failed to send to recipient');
      failedRecipients.push(recipient.email)
    }
  }
  if (failedRecipients.length === recipients.length) {
    throw new APIError('SendMessagePerRecipient: Sending failed for all recipients', 500);
  }
  return {failedRecipients}
}

/**
 * This enables customized link and open tracking on a per-recipient basis
 * by delivering several messages to each recipient.
 *
 * Errors in this task always mean the all messages failed to send to all
 * receipients.
 *
 * If it failed to some recipients, we return a `failedRecipients` array
 * to notify the user.
 *
 * We later get EnsureMessageInSentFolder queued with the
 * `sentPerRecipient` flag set to ensure the newly delivered message shows
 * up in the sent folder and only a single message shows up in the sent
 * folder.
 */
class SendMessagePerRecipientSMTP extends SyncbackTask {
  description() {
    return `SendMessagePerRecipient`;
  }

  affectsImapMessageUIDs() {
    return false
  }

  async run(db) {
    const {
      messagePayload,
      usesOpenTracking,
      usesLinkTracking,
    } = this.syncbackRequestObject().props
    const account = this._account

    const baseMessage = await MessageFactory.buildForSend(db, messagePayload)

    const sendResult = await sendPerRecipient({db, account, baseMessage, usesOpenTracking, usesLinkTracking})

    /**
     * Once messages have actually been delivered, we need to be very
     * careful not to throw an error from this task. An Error in the send
     * task implies failed delivery and the prompting of users to try
     * again.
     */
    try {
      // We strip the tracking links because this is the message that we want to
      // show the user as sent, so it shouldn't contain the tracking links
      baseMessage.body = MessageFactory.stripTrackingLinksFromBody(baseMessage.body)

      baseMessage.setIsSent(true)

      // We don't save the message until after successfully sending it.
      // In the next sync loop, the message's labels and other data will
      // be updated, and we can guarantee this because we control message
      // id generation. The thread will be created or updated when we
      // detect this message in the sync loop
      await baseMessage.save()

      return {
        message: baseMessage.toJSON(),
        failedRecipients: sendResult.failedRecipients,
      }
    } catch (err) {
      this._logger.error('SendMessagePerRecipient: Failed to save the baseMessage to local sync database after it was successfully delivered', err);
      return {message: {}, failedRecipients: []}
    }
  }
}

module.exports = SendMessagePerRecipientSMTP;
