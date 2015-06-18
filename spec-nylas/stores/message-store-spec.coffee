_ = require 'underscore'
Thread = require '../../src/flux/models/thread'
Message = require '../../src/flux/models/message'
FocusedContentStore = require '../../src/flux/stores/focused-content-store'
MessageStore = require '../../src/flux/stores/message-store'
DatabaseStore = require '../../src/flux/stores/database-store'
MarkThreadReadTask = require '../../src/flux/tasks/mark-thread-read'
Actions = require '../../src/flux/actions'

testThread = new Thread(id: '123')
testMessage1 = new Message(id: 'a', body: '123', files: [])
testMessage2 = new Message(id: 'b', body: '123', files: [])

describe "MessageStore", ->
  describe "when thread focus changes", ->
    beforeEach ->
      @focus = null
      spyOn(FocusedContentStore, 'focused').andCallFake (collection) =>
        if collection is 'thread'
          @focus
        else
          null

      spyOn(FocusedContentStore, 'focusedId').andCallFake (collection) =>
        if collection is 'thread'
          @focus?.id
        else
          null

      spyOn(DatabaseStore, 'findAll').andCallFake ->
        include: -> @
        evaluateImmediately: -> @
        then: (callback) -> callback([testMessage1, testMessage2])

    it "should retrieve the focused thread", ->
      @focus = testThread
      FocusedContentStore.trigger({impactsCollection: -> true})
      expect(DatabaseStore.findAll).toHaveBeenCalled()
      expect(DatabaseStore.findAll.mostRecentCall.args[0]).toBe(Message)

    describe "when the thread is unread", ->
      beforeEach ->
        @focus = null
        FocusedContentStore.trigger({impactsCollection: -> true})
        spyOn(testThread, 'isUnread').andCallFake -> true
        spyOn(Actions, 'queueTask')

      it "should queue a task to mark the thread as read", ->
        @focus = testThread
        FocusedContentStore.trigger({impactsCollection: -> true})
        advanceClock(500)
        expect(Actions.queueTask).not.toHaveBeenCalled()
        advanceClock(500)
        expect(Actions.queueTask).toHaveBeenCalled()
        expect(Actions.queueTask.mostRecentCall.args[0] instanceof MarkThreadReadTask).toBe(true)

      it "should not queue a task to mark the thread as read if the thread is no longer selected 500msec later", ->
        @focus = testThread
        FocusedContentStore.trigger({impactsCollection: -> true})
        advanceClock(500)
        expect(Actions.queueTask).not.toHaveBeenCalled()
        @focus = null
        FocusedContentStore.trigger({impactsCollection: -> true})
        advanceClock(500)
        expect(Actions.queueTask).not.toHaveBeenCalled()
