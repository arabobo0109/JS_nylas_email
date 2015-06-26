fs = require 'fs'
_ = require 'underscore'
pathUtils = require 'path'
Task = require './task'
File = require '../models/file'
Message = require '../models/message'
Actions = require '../actions'
NamespaceStore = require '../stores/namespace-store'
DatabaseStore = require '../stores/database-store'
{isTempId} = require '../models/utils'
NylasAPI = require '../nylas-api'
Utils = require '../models/utils'

idGen = 2

class FileUploadTask extends Task

  @idGen: -> idGen

  constructor: (@filePath, @messageLocalId) ->
    super
    @_startedUploadingAt = Date.now()
    @_uploadId = FileUploadTask.idGen()
    idGen += 1
    @progress = null # The progress checking timer.

  performLocal: ->
    return Promise.reject(new Error("Must pass an absolute path to upload")) unless @filePath?.length
    return Promise.reject(new Error("Must be attached to a messageLocalId")) unless isTempId(@messageLocalId)
    Actions.uploadStateChanged @_uploadData("pending")
    Promise.resolve()

  performRemote: ->
    new Promise (resolve, reject) =>
      Actions.uploadStateChanged @_uploadData("started")

      @req = NylasAPI.makeRequest
        path: "/n/#{@_namespaceId()}/files"
        method: "POST"
        json: false
        formData: @_formData()
        error: reject
        success: (rawResponseString) =>
          # The Nylas API returns the file json wrapped in an array.
          #
          # Since we requested `json:false` the response will come back as
          # a raw string.
          try
            json = JSON.parse(rawResponseString)
            file = (new File).fromJSON(json[0])
          catch error
            reject(error)
          @_onRemoteSuccess(file, resolve, reject)

      @progress = setInterval =>
        Actions.uploadStateChanged(@_uploadData("progress"))
      , 250

  cleanup: ->
    super

    # If the request is still in progress, notify observers that
    # we've failed.
    if @req
      @req.abort()
      clearInterval(@progress)
      Actions.uploadStateChanged(@_uploadData("aborted"))
      setTimeout =>
        # To see the aborted state for a little bit
        Actions.fileAborted(@_uploadData("aborted"))
      , 1000

  onAPIError: (apiError) ->
    @_rollbackLocal()

  onOtherError: (otherError) ->
    @_rollbackLocal()

  onTimeoutError: ->
    # Do nothing. It could take a while.
    Promise.resolve()

  onOfflineError: (offlineError) ->
    msg = "You can't upload a file while you're offline."
    @_rollbackLocal(msg)

  _rollbackLocal: (msg) ->
    clearInterval(@progress)
    @req = null

    msg ?= "There was a problem uploading this file. Please try again later."
    Actions.postNotification({message: msg, type: "error"})
    Actions.uploadStateChanged @_uploadData("failed")

  _onRemoteSuccess: (file, resolve, reject) =>
    clearInterval(@progress)
    @req = null

    # The minute we know what file is associated with the upload, we need
    # to fire an Action to notify a popout window's FileUploadStore that
    # these two objects are linked. We unfortunately can't wait until
    # `_attacheFileToDraft` resolves, because that will resolve after the
    # DB transaction is completed AND all of the callbacks have fired.
    # Unfortunately in the callback chain is a render method which means
    # that the upload will be left on the page for a split second before
    # we know the file has been uploaded.
    #
    # Associating the upload with the file ahead of time can let the
    # Composer know which ones to ignore when de-duping the upload/file
    # listing.
    Actions.linkFileToUpload(file: file, uploadData: @_uploadData("completed"))

    @_attachFileToDraft(file).then =>
      Actions.uploadStateChanged @_uploadData("completed")
      Actions.fileUploaded(file: file, uploadData: @_uploadData("completed"))
      resolve()
    .catch(reject)

  _attachFileToDraft: (file) ->
    DraftStore = require '../stores/draft-store'
    DraftStore.sessionForLocalId(@messageLocalId).then (session) =>
      files = _.clone(session.draft().files) ? []
      files.push(file)
      session.changes.add({files})
      return session.changes.commit()

  _formData: ->
    file: # Must be named `file` as per the Nylas API spec
      value: fs.createReadStream(@filePath)
      options:
        filename: @_uploadData().fileName

  # returns:
  #   messageLocalId - The localId of the message (draft) we're uploading to
  #   filePath - The full absolute local system file path
  #   fileSize - The size in bytes
  #   fileName - The basename of the file
  #   bytesUploaded - Current number of bytes uploaded
  #   state - one of "pending" "started" "progress" "completed" "aborted" "failed"
  _uploadData: (state) ->
    @_memoUploadData ?=
      uploadId: @_uploadId
      startedUploadingAt: @_startedUploadingAt
      messageLocalId: @messageLocalId
      filePath: @filePath
      fileSize: @_getFileSize(@filePath)
      fileName: pathUtils.basename(@filePath)
    @_memoUploadData.bytesUploaded = @_getBytesUploaded()
    @_memoUploadData.state = state if state?
    return _.extend({}, @_memoUploadData)

  _getFileSize: (path) ->
    fs.statSync(path)["size"]

  _getBytesUploaded: ->
    # https://github.com/request/request/issues/941
    # http://stackoverflow.com/questions/12098713/upload-progress-request
    @req?.req?.connection?._bytesDispatched ? 0

  _namespaceId: -> NamespaceStore.current()?.id

module.exports = FileUploadTask
