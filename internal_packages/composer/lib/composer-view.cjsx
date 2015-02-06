_ = require 'underscore-plus'

React = require 'react'

{Actions,
 ContactStore,
 FileUploadStore,
 ComponentRegistry} = require 'inbox-exports'

FileUploads = require './file-uploads.cjsx'
DraftStoreProxy = require './draft-store-proxy'
ContenteditableToolbar = require './contenteditable-toolbar.cjsx'
ContenteditableComponent = require './contenteditable-component.cjsx'
ComposerParticipants = require './composer-participants.cjsx'


# The ComposerView is a unique React component because it (currently) is a
# singleton. Normally, the React way to do things would be to re-render the
# Composer with new props. As an alternative, we can call `setProps` to
# simulate the effect of the parent re-rendering us
module.exports =
ComposerView = React.createClass

  getInitialState: ->
    # A majority of the initial state is set in `_setInitialState` because
    # those getters are asynchronous while `getInitialState` is
    # synchronous.
    state = @getComponentRegistryState()
    _.extend state,
      populated: false
      to: undefined
      cc: undefined
      bcc: undefined
      body: undefined
      subject: undefined
    state

  getComponentRegistryState: ->
    ResizableComponent: ComponentRegistry.findViewByName 'ResizableComponent'
    MessageAttachment: ComponentRegistry.findViewByName 'MessageAttachment'
    FooterComponents: ComponentRegistry.findAllViewsByRole 'Composer:Footer'

  componentWillMount: ->
    @_prepareForDraft()

  componentWillUnmount: ->
    @_teardownForDraft()

  componentWillReceiveProps: (newProps) ->
    if newProps.localId != @props.localId
      # When we're given a new draft localId, we have to stop listening to our
      # current DraftStoreProxy, create a new one and listen to that. The simplest
      # way to do this is to just re-call registerListeners.
      @_teardownForDraft()
      @_prepareForDraft()

  _prepareForDraft: ->
    @_proxy = new DraftStoreProxy(@props.localId)

    @unlisteners = []
    @unlisteners.push @_proxy.listen(@_onDraftChanged)
    @unlisteners.push ComponentRegistry.listen (event) =>
      @setState(@getComponentRegistryState())

  _teardownForDraft: ->
    unlisten() for unlisten in @unlisteners
    @_proxy.changes.commit()

  render: ->
    ResizableComponent = @state.ResizableComponent

    if @props.mode is "inline" and ResizableComponent?
      <div className={@_wrapClasses()}>
        <ResizableComponent position="bottom" barStyle={bottom: "57px", zIndex: 2}>
          {@_renderComposer()}
        </ResizableComponent>
      </div>
    else
      <div className={@_wrapClasses()}>
        {@_renderComposer()}
      </div>

  _wrapClasses: ->
    "composer-outer-wrap #{@props.containerClass ? ""}"

  _renderComposer: ->
    # Do not render the composer unless we have loaded our draft.
    # Otherwise the Scribe component is initialized with HTML = ""
    return <div></div> if @state.body == undefined

    <div className="composer-inner-wrap">

      <div className="composer-header">
        <div className="composer-title">
          {@_composerTitle()}
        </div>
        <div className="composer-header-actions">
          <span
            className="header-action"
            style={display: @state.showcc and 'none' or 'inline'}
            onClick={=> @setState {showcc: true}}
            >Add cc/bcc</span>
          <span
            className="header-action"
            style={display: @state.showsubject and 'none' or 'initial'}
            onClick={=> @setState {showsubject: true}}
          >Change Subject</span>
          <span
            className="header-action"
            style={display: (@props.mode is "fullwindow") and 'none' or 'initial'}
            onClick={@_popoutComposer}
          >Popout&nbsp&nbsp;<i className="fa fa-expand"></i></span>
        </div>
      </div>

      <div className="compose-participants-wrap">
        <ComposerParticipants name="to"
                      tabIndex="101"
                      participants={@state.to}
                      participantFunctions={@_participantFunctions('to')}
                      placeholder="To" />
      </div>

      <div className="compose-participants-wrap"
           style={display: @state.showcc and 'initial' or 'none'}>
        <ComposerParticipants name="cc"
                      tabIndex="102"
                      disabled={not @state.showcc}
                      participants={@state.cc}
                      participantFunctions={@_participantFunctions('cc')}
                      placeholder="Cc" />
      </div>

      <div className="compose-participants-wrap"
           style={display: @state.showcc and 'initial' or 'none'}>
        <ComposerParticipants name="bcc"
                      tabIndex="103"
                      disabled={not @state.showcc}
                      participants={@state.bcc}
                      participantFunctions={@_participantFunctions('bcc')}
                      placeholder="Bcc" />
      </div>

      <div className="compose-subject-wrap"
           style={display: @state.showsubject and 'initial' or 'none'}>
        <input type="text"
               key="subject"
               name="subject"
               placeholder="Subject"
               tabIndex="108"
               disabled={not @state.showsubject}
               className="compose-field compose-subject"
               defaultValue={@state.subject}
               onChange={@_onChangeSubject}/>
      </div>

      <div className="compose-body"
           onClick={@_onComposeBodyClick}>
        <ContenteditableComponent ref="scribe"
                             onChange={@_onChangeBody}
                             html={@state.body}
                             tabIndex="109" />
      </div>

      <div className="attachments-area" >
        {@_fileComponents()}
        <FileUploads localId={@props.localId} />
      </div>

      <div className="compose-footer">
        <button className="btn btn-icon pull-right"
                onClick={@_destroyDraft}><i className="fa fa-trash"></i></button>
        <button className="btn btn-send"
                tabIndex="110"
                onClick={@_sendDraft}><i className="fa fa-send"></i>&nbsp;Send</button>
        <ContenteditableToolbar />
        <button className="btn btn-icon"
                onClick={@_attachFile}><i className="fa fa-paperclip"></i></button>
        {@_footerComponents()}
      </div>
    </div>

  # TODO, in the future this will be smarter and say useful things like
  # "Reply" or "Reply All" or "Reply + New Person1, New Person2"
  _composerTitle: -> "Compose Message"

  _footerComponents: ->
    (@state.FooterComponents ? []).map (Component) =>
      <Component draftLocalId={@props.localId} />

  _onDraftChanged: ->
    draft = @_proxy.draft()
    state =
      to: draft.to
      cc: draft.cc
      bcc: draft.bcc
      files: draft.files
      subject: draft.subject
      body: draft.body

    if !@state.populated
      _.extend state,
        showcc: (not (_.isEmpty(draft.cc) and _.isEmpty(draft.bcc)))
        showsubject: _.isEmpty(draft.subject)
        populated: true

    @setState(state)

  _popoutComposer: ->
    Actions.composePopoutDraft @props.localId

  _onComposeBodyClick: ->
    @refs.scribe.focus()

  _onChangeSubject: (event) ->
    @_proxy.changes.add(subject: event.target.value)

  _onChangeBody: (event) ->
    @_proxy.changes.add(body: event.target.value)

  _participantFunctions: (field) ->
    remove: (participant) =>
      updates = {}
      updates[field] = _.without(@state[field], participant)
      @_proxy.changes.add(updates)

    add: (participant) =>
      updates = {}
      updates[field] = _.union (@state[field] ? []), [participant]
      @_proxy.changes.add(updates)
      ""

  _sendDraft: ->
    @_proxy.changes.commit()
    Actions.sendDraft(@props.localId)

  _destroyDraft: ->
    Actions.destroyDraft(@props.localId)

  _attachFile: ->
    Actions.attachFile({messageLocalId: @props.localId})

  _fileComponents: ->
    MessageAttachment = @state.MessageAttachment
    (@state.files ? []).map (file) =>
      <MessageAttachment file={file}
                         removable={true}
                         messageLocalId={@props.localId} />
