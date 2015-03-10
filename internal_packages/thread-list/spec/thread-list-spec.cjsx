moment = require "moment"
_ = require 'underscore-plus'
CSON = require 'season'
React = require "react/addons"
ReactTestUtils = React.addons.TestUtils
ReactTestUtils = _.extend ReactTestUtils, require "jasmine-react-helpers"

{Thread,
 Actions,
 Namespace,
 ThreadStore,
 DatabaseStore,
 InboxTestUtils,
 NamespaceStore,
 ComponentRegistry} = require "inbox-exports"
{ListTabular} = require 'ui-components'

ThreadList = require "../lib/thread-list.cjsx"

ParticipantsItem = React.createClass
  render: -> <div></div>

me = new Namespace(
  "name": "User One",
  "email": "user1@inboxapp.com"
  "provider": "inbox"
)
NamespaceStore._current = me

test_threads = -> [
  (new Thread).fromJSON({
    "id": "111",
    "object": "thread",
    "created_at": null,
    "updated_at": null,
    "namespace_id": "nsid",
    "snippet": "snippet 111",
    "subject": "Subject 111",
    "tags": [
      {
        "id": "unseen",
        "created_at": null,
        "updated_at": null,
        "name": "unseen"
      },
      {
        "id": "all",
        "created_at": null,
        "updated_at": null,
        "name": "all"
      },
      {
        "id": "inbox",
        "created_at": null,
        "updated_at": null,
        "name": "inbox"
      },
      {
        "id": "unread",
        "created_at": null,
        "updated_at": null,
        "name": "unread"
      },
      {
        "id": "attachment",
        "created_at": null,
        "updated_at": null,
        "name": "attachment"
      }
    ],
    "participants": [
      {
        "created_at": null,
        "updated_at": null,
        "name": "User One",
        "email": "user1@inboxapp.com"
      },
      {
        "created_at": null,
        "updated_at": null,
        "name": "User Two",
        "email": "user2@inboxapp.com"
      }
    ],
    "last_message_timestamp": 1415742036
  }),
  (new Thread).fromJSON({
    "id": "222",
    "object": "thread",
    "created_at": null,
    "updated_at": null,
    "namespace_id": "nsid",
    "snippet": "snippet 222",
    "subject": "Subject 222",
    "tags": [
      {
        "id": "unread",
        "created_at": null,
        "updated_at": null,
        "name": "unread"
      },
      {
        "id": "all",
        "created_at": null,
        "updated_at": null,
        "name": "all"
      },
      {
        "id": "unseen",
        "created_at": null,
        "updated_at": null,
        "name": "unseen"
      },
      {
        "id": "inbox",
        "created_at": null,
        "updated_at": null,
        "name": "inbox"
      }
    ],
    "participants": [
      {
        "created_at": null,
        "updated_at": null,
        "name": "User One",
        "email": "user1@inboxapp.com"
      },
      {
        "created_at": null,
        "updated_at": null,
        "name": "User Three",
        "email": "user3@inboxapp.com"
      }
    ],
    "last_message_timestamp": 1415741913
  }),
  (new Thread).fromJSON({
    "id": "333",
    "object": "thread",
    "created_at": null,
    "updated_at": null,
    "namespace_id": "nsid",
    "snippet": "snippet 333",
    "subject": "Subject 333",
    "tags": [
      {
        "id": "inbox",
        "created_at": null,
        "updated_at": null,
        "name": "inbox"
      },
      {
        "id": "all",
        "created_at": null,
        "updated_at": null,
        "name": "all"
      },
      {
        "id": "unseen",
        "created_at": null,
        "updated_at": null,
        "name": "unseen"
      }
    ],
    "participants": [
      {
        "created_at": null,
        "updated_at": null,
        "name": "User One",
        "email": "user1@inboxapp.com"
      },
      {
        "created_at": null,
        "updated_at": null,
        "name": "User Four",
        "email": "user4@inboxapp.com"
      }
    ],
    "last_message_timestamp": 1415741837
  })
]





cjsxSubjectResolver = (thread) ->
  <div>
    <span>Subject {thread.id}</span>
    <span className="snippet">Snippet</span>
  </div>

describe "ThreadList", ->

  Foo = React.createClass({render: -> <div>{@props.children}</div>})
  c1 = new ListTabular.Column
    name: "Name"
    flex: 1
    resolver: (thread) -> "#{thread.id} Test Name"
  c2 = new ListTabular.Column
    name: "Subject"
    flex: 3
    resolver: cjsxSubjectResolver
  c3 = new ListTabular.Column
    name: "Date"
    resolver: (thread) -> <Foo>{thread.id}</Foo>

  columns = [c1,c2,c3]

  beforeEach ->
    InboxTestUtils.loadKeymap("internal_packages/thread-list/keymaps/thread-list.cson")
    spyOn(ThreadStore, "_onNamespaceChanged")
    spyOn(DatabaseStore, "findAll").andCallFake ->
      new Promise (resolve, reject) -> resolve(test_threads())
    ReactTestUtils.spyOnClass(ThreadList, "_computeColumns").andReturn(columns)

    ThreadStore._resetInstanceVars()

    ComponentRegistry.register
      name: 'Participants'
      view: ParticipantsItem

    @thread_list = ReactTestUtils.renderIntoDocument(
      <ThreadList />
    )

  it "renders into the document", ->
    expect(ReactTestUtils.isCompositeComponentWithType(@thread_list,
                                          ThreadList)).toBe true

  it "stars on keymap", ->
    spyOn(@thread_list, "_onStarThread")
    InboxTestUtils.keyPress("s", @thread_list.getDOMNode())
    expect(@thread_list._onStarThread).toHaveBeenCalled()

  it "has the expected columns", ->
    expect(@thread_list.state.columns).toEqual columns

  it "by default has zero children", ->
    items = ReactTestUtils.scryRenderedComponentsWithType(@thread_list, ListTabular.Item)
    expect(items.length).toBe 0

  describe "Populated thread list", ->
    beforeEach ->
      ThreadStore._items = test_threads()
      ThreadStore._selectedId = null
      ThreadStore.trigger(ThreadStore)
      @thread_list_node = @thread_list.getDOMNode()

    it "renders all of the thread list items", ->
      items = ReactTestUtils.scryRenderedComponentsWithType(@thread_list, ListTabular.Item)
      expect(items.length).toBe 3


# describe "ThreadListNarrow", ->

#   beforeEach ->
#     InboxTestUtils.loadKeymap("internal_packages/thread-list/keymaps/thread-list.cson")
#     spyOn(ThreadStore, "_onNamespaceChanged")
#     spyOn(DatabaseStore, "findAll").andCallFake ->
#       new Promise (resolve, reject) -> resolve(test_threads())
#     ThreadStore._resetInstanceVars()

#     ComponentRegistry.register
#       name: 'Participants'
#       view: ParticipantsItem

#     @thread_list = ReactTestUtils.renderIntoDocument(
#       <ThreadListNarrow />
#     )

#   it "renders into the document", ->
#     expect(ReactTestUtils.isCompositeComponentWithType(@thread_list,
#                                           ThreadListNarrow)).toBe true

#   it "by default has zero children", ->
#     items = ReactTestUtils.scryRenderedComponentsWithType(@thread_list,
#                                              ThreadListNarrowItem)
#     expect(items.length).toBe 0

#   describe "Populated thread list", ->
#     beforeEach ->
#       ThreadStore._items = test_threads()
#       ThreadStore._selectedId = null
#       ThreadStore.trigger()
#       @thread_list_node = @thread_list.getDOMNode()

#     it "renders all of the thread list items", ->
#       items = ReactTestUtils.scryRenderedComponentsWithType(@thread_list,
#                                                ThreadListNarrowItem)
#       expect(items.length).toBe 3

#     describe "Shifting selected index", ->

#       beforeEach ->
#         spyOn(@thread_list, "_onShiftSelectedIndex")
#         spyOn(Actions, "selectThreadId")

#       it "can move selection up", ->
#         atom.commands.dispatch(document.body, "application:previous-item")
#         expect(@thread_list._onShiftSelectedIndex).toHaveBeenCalledWith(-1)

#       it "can move selection down", ->
#         atom.commands.dispatch(document.body, "application:next-item")
#         expect(@thread_list._onShiftSelectedIndex).toHaveBeenCalledWith(1)

#     describe "Triggering message list commands", ->
#       beforeEach ->
#         spyOn(Actions, "composeReply")
#         spyOn(Actions, "composeReplyAll")
#         spyOn(Actions, "composeForward")
#         ThreadStore._onSelectThreadId("111")
#         @thread = ThreadStore.selectedThread()
#         spyOn(@thread, "archive")
#         spyOn(@thread_list, "_onShiftSelectedIndex")
#         spyOn(Actions, "selectThreadId")

#       it "can reply to the currently selected thread", ->
#         atom.commands.dispatch(document.body, "application:reply")
#         expect(Actions.composeReply).toHaveBeenCalledWith(threadId: @thread.id)

#       it "can reply all to the currently selected thread", ->
#         atom.commands.dispatch(document.body, "application:reply-all")
#         expect(Actions.composeReplyAll).toHaveBeenCalledWith(threadId: @thread.id)

#       it "can forward the currently selected thread", ->
#         atom.commands.dispatch(document.body, "application:forward")
#         expect(Actions.composeForward).toHaveBeenCalledWith(threadId: @thread.id)

#       it "can archive the currently selected thread", ->
#         atom.commands.dispatch(document.body, "application:remove-item")
#         expect(@thread.archive).toHaveBeenCalled()

#       it "can archive the currently selected thread and navigate up", ->
#         atom.commands.dispatch(document.body, "application:remove-and-previous")
#         expect(@thread.archive).toHaveBeenCalled()
#         expect(@thread_list._onShiftSelectedIndex).toHaveBeenCalledWith(-1)

#       it "does nothing when no thread is selected", ->
#         ThreadStore._selectedId = null
#         atom.commands.dispatch(document.body, "application:reply")
#         expect(Actions.composeReply.calls.length).toEqual(0)

#     describe "ThreadListNarrowItem", ->
#       beforeEach ->
#         items = ReactTestUtils.scryRenderedComponentsWithType(@thread_list,
#                                                  ThreadListNarrowItem)
#         item = items.filter (tli) -> tli.props.thread.id is "111"
#         @thread_list_item = item[0]
#         @thread_date = moment(@thread_list_item.props.thread.lastMessageTimestamp)

#       it "finds the thread list item by id", ->
#         expect(@thread_list_item.props.thread.id).toBe "111"

#       it "fires the appropriate Action on click", ->
#         spyOn(Actions, "selectThreadId")
#         ReactTestUtils.Simulate.click @thread_list_item.getDOMNode()
#         expect(Actions.selectThreadId).toHaveBeenCalledWith("111")

#       it "sets the selected state on the thread item", ->
#         ThreadStore._onSelectThreadId("111")
#         items = ReactTestUtils.scryRenderedDOMComponentsWithClass(@thread_list, "selected")
#         expect(items.length).toBe 1
#         expect(items[0].props.id).toBe "111"

#       it "renders de-selection when invalid id is emitted", ->
#         ThreadStore._onSelectThreadId('abc')
#         items = ReactTestUtils.scryRenderedDOMComponentsWithClass(@thread_list, "selected")
#         expect(items.length).toBe 0

#       # test "last_message_timestamp": 1415742036
#       it "displays the time from threads LONG ago", ->
#         spyOn(@thread_list_item, "_today").andCallFake =>
#           @thread_date.add(2, 'years')
#         expect(@thread_list_item._timeFormat()).toBe "MMM D YYYY"

#       it "displays the time from threads a bit ago", ->
#         spyOn(@thread_list_item, "_today").andCallFake =>
#           @thread_date.add(2, 'days')
#         expect(@thread_list_item._timeFormat()).toBe "MMM D"

#       it "displays the time from threads exactly a day ago", ->
#         spyOn(@thread_list_item, "_today").andCallFake =>
#           @thread_date.add(1, 'day')
#         expect(@thread_list_item._timeFormat()).toBe "h:mm a"

#       it "displays the time from threads recently", ->
#         spyOn(@thread_list_item, "_today").andCallFake =>
#           @thread_date.add(2, 'hours')
#         expect(@thread_list_item._timeFormat()).toBe "h:mm a"
