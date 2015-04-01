Reflux = require "reflux"
Actions = require "../actions"
Message = require "../models/message"
DatabaseStore = require "./database-store"
NamespaceStore = require "./namespace-store"
async = require 'async'
_ = require 'underscore-plus'

MessageStore = Reflux.createStore
  init: ->
    @_setStoreDefaults()
    @_registerListeners()


  ########### PUBLIC #####################################################

  items: ->
    @_items

  threadId: -> @_thread?.id
  
  thread: -> @_thread

  itemsExpandedState: ->
    # ensure that we're always serving up immutable objects.
    # this.state == nextState is always true if we modify objects in place.
    _.clone @_itemsExpanded

  itemLocalIds: ->
    _.clone @_itemsLocalIds

  itemsLoading: ->
    @_itemsLoading

  ########### PRIVATE ####################################################

  _setStoreDefaults: ->
    @_items = []
    @_itemsExpanded = {}
    @_itemsLocalIds = {}
    @_itemsLoading = false
    @_thread = null
    @_inflight = {}

  _registerListeners: ->
    @listenTo DatabaseStore, @_onDataChanged
    @listenTo Actions.focusThread, @_onFocusThread
    @listenTo Actions.toggleMessageIdExpanded, @_onToggleMessageIdExpanded

  _onDataChanged: (change) ->
    return unless change.objectClass == Message.name
    return unless @_thread
    inDisplayedThread = _.some change.objects, (obj) =>
      obj.threadId == @_thread.id
    return unless inDisplayedThread
    @_fetchFromCache()

  _onFocusThread: (thread) ->
    return if @_thread?.id is thread?.id

    @_thread = thread
    @_items = []
    @_itemsLoading = true
    @_itemsExpanded = {}
    @trigger()

    @_fetchFromCache()

  _onToggleMessageIdExpanded: (id) ->
    if @_itemsExpanded[id]
      delete @_itemsExpanded[id]
    else
      @_itemsExpanded[id] = true
      for item, idx in @_items
        if @_itemsExpanded[item.id] and not _.isString(item.body)
          @_fetchMessageIdFromAPI(item.id)

    @trigger()

  _fetchFromCache: (options = {}) ->
    return unless @_thread

    loadedThreadId = @_thread.id

    query = DatabaseStore.findAll(Message, threadId: loadedThreadId)
    query.include(Message.attributes.body)
    query.evaluateImmediately()
    query.then (items) =>
      localIds = {}
      async.each items, (item, callback) ->
        return callback() unless item.draft
        DatabaseStore.localIdForModel(item).then (localId) ->
          localIds[item.id] = localId
          callback()
      , =>
        # Check to make sure that our thread is still the thread we were
        # loading items for. Necessary because this takes a while.
        return unless loadedThreadId == @_thread.id

        loaded = true

        @_items = @_sortItemsForDisplay(items)
        @_itemsLocalIds = localIds

        # If no items were returned, attempt to load messages via the API. If items
        # are returned, this will trigger a refresh here.
        if @_items.length is 0
          namespace = NamespaceStore.current()
          atom.inbox.getCollection namespace.id, 'messages', {thread_id: @_thread.id}
          loaded = false

        @_expandItemsToDefault()

        # Check that expanded messages have bodies. We won't mark ourselves
        # as loaded until they're all available. Note that items can be manually
        # expanded so this logic must be separate from above.
        for item, idx in @_items
          if @_itemsExpanded[item.id] and not _.isString(item.body)
            @_fetchMessageIdFromAPI(item.id)
            loaded = false

        # Start fetching inline image attachments. Note that the download store
        # is smart enough that calling this multiple times is not bad!
        for msg in items
          for file in msg.files
            Actions.fetchFile(file) if file.contentId

        # Normally, we would trigger often and let the view's
        # shouldComponentUpdate decide whether to re-render, but if we
        # know we're not ready, don't even bother.  Trigger once at start
        # and once when ready. Many third-party stores will observe
        # MessageStore and they'll be stupid and re-render constantly.
        if loaded
          @_itemsLoading = false
          @trigger(@)

  # Expand all unread messages, all drafts, and the last message
  _expandItemsToDefault: ->
    for item, idx in @_items
      if item.unread or item.draft or idx is @_items.length - 1
        @_itemsExpanded[item.id] = true

  _fetchMessageIdFromAPI: (id) ->
    return if @_inflight[id]

    @_inflight[id] = true
    namespace = NamespaceStore.current()
    atom.inbox.makeRequest
      path: "/n/#{namespace.id}/messages/#{id}"
      returnsModel: true
      success: =>
        delete @_inflight[id]

  _sortItemsForDisplay: (items) ->
    # Re-sort items in the list so that drafts appear after the message that
    # they are in reply to, when possible. First, identify all the drafts
    # with a replyToMessageId and remove them
    itemsInReplyTo = []
    for item, index in items by -1
      if item.draft and item.replyToMessageId
        itemsInReplyTo.push(item)
        items.splice(index, 1)

    # For each item with the reply header, re-inset it into the list after
    # the message which it was in reply to. If we can't find it, put it at the end.
    for item in itemsInReplyTo
      for other, index in items
        if item.replyToMessageId is other.id
          items.splice(index+1, 0, item)
          item = null
          break
      if item
        items.push(item)

    items

module.exports = MessageStore
