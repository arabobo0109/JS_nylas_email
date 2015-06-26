React = require 'react'
{Actions, NamespaceStore} = require 'nylas-exports'
{RetinaImg, ButtonDropdown} = require 'nylas-component-kit'

class MessageControls extends React.Component
  @displayName: "MessageControls"
  @propTypes:
    thread: React.PropTypes.object.isRequired
    message: React.PropTypes.object.isRequired

  constructor: (@props) ->

  render: =>
    button = []

    if @_replyType() is "reply"
      button = <ButtonDropdown
        primaryItem={<RetinaImg name="reply-footer.png" mode={RetinaImg.Mode.ContentIsMask}/>}
        primaryClick={@_onReply}
        secondaryItems={@_secondaryMessageActions()}/>
    else
      button = <ButtonDropdown
        primaryItem={<RetinaImg name="reply-all-footer.png" mode={RetinaImg.Mode.ContentIsMask}/>}
        primaryClick={@_onReplyAll}
        secondaryItems={@_secondaryMessageActions()}/>

    <div className="message-actions-wrap">
      <div className="message-actions-ellipsis" onClick={@_onShowActionsMenu}>
        <RetinaImg name={"message-actions-ellipsis.png"} mode={RetinaImg.Mode.ContentIsMask}/>
      </div>
      {button}
    </div>

  _primaryMessageAction: =>
    if @_replyType() is "reply"
      <div className="primary-message-action" onClick={@_onReply}>
        <RetinaImg name="reply-footer.png" mode={RetinaImg.Mode.ContentIsMask}/>
      </div>
    else # if "reply-all"
      <div className="primary-message-action" onClick={@_onReplyAll}>
        <RetinaImg name="reply-all-footer.png" mode={RetinaImg.Mode.ContentIsMask}/>
      </div>

  _secondaryMessageActions: ->
    if @_replyType() is "reply"
      return [@_replyAllAction(), @_forwardAction()]
    else #if "reply-all"
      return [@_replyAction(), @_forwardAction()]

  _forwardAction: ->
    <span onClick={@_onForward}>
      <RetinaImg name="icon-dropdown-forward.png" mode={RetinaImg.Mode.ContentIsMask}/>&nbsp;&nbsp;Forward
    </span>
  _replyAction: ->
    <span onClick={@_onReply}>
      <RetinaImg name="icon-dropdown-reply.png" mode={RetinaImg.Mode.ContentIsMask}/>&nbsp;&nbsp;Reply
    </span>
  _replyAllAction: ->
    <span onClick={@_onReplyAll}>
      <RetinaImg name="icon-dropdown-replyall.png" mode={RetinaImg.Mode.ContentIsMask}/>&nbsp;&nbsp;Reply All
    </span>

  _onReply: =>
    Actions.composeReply(thread: @props.thread, message: @props.message)

  _onReplyAll: =>
    Actions.composeReplyAll(thread: @props.thread, message: @props.message)

  _onForward: =>
    Actions.composeForward(thread: @props.thread, message: @props.message)

  _replyType: =>
    emails = @props.message.to.map (item) -> item.email.toLowerCase().trim()
    myEmail = NamespaceStore.current()?.me().email.toLowerCase().trim()
    if @props.message.cc.length is 0 and @props.message.to.length is 1 and emails[0] is myEmail
      return "reply"
    else return "reply-all"

module.exports = MessageControls

      # <InjectedComponentSet className="message-actions"
      #                       inline={true}
      #                       matching={role:"MessageAction"}
      #                       exposedProps={thread:@props.thread, message: @props.message}>
      #   <button className="btn btn-icon" onClick={@_onReply}>
      #     <RetinaImg name={"message-reply.png"} mode={RetinaImg.Mode.ContentIsMask}/>
      #   </button>
      #   <button className="btn btn-icon" onClick={@_onReplyAll}>
      #     <RetinaImg name={"message-reply-all.png"} mode={RetinaImg.Mode.ContentIsMask}/>
      #   </button>
      #   <button className="btn btn-icon" onClick={@_onForward}>
      #     <RetinaImg name={"message-forward.png"} mode={RetinaImg.Mode.ContentIsMask}/>
      #   </button>
      # </InjectedComponentSet>
