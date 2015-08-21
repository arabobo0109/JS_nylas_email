_ = require 'underscore'
React = require 'react/addons'
ReactTestUtils = React.addons.TestUtils
proxyquire = require 'proxyquire'

{NylasTestUtils,
 AccountStore,
 ContactStore,
 Contact,
 Utils,
} = require 'nylas-exports'

ParticipantsTextField = proxyquire '../lib/participants-text-field',
  'nylas-exports': {Contact, ContactStore}

participant1 = new Contact
  email: 'ben@nylas.com'
participant2 = new Contact
  email: 'ben@example.com'
  name: 'Ben Gotow'
participant3 = new Contact
  email: 'evan@nylas.com'
  name: 'Evan Morikawa'
participant4 = new Contact
  email: 'ben@elsewhere.com',
  name: 'ben Again'
participant5 = new Contact
  email: 'evan@elsewhere.com',
  name: 'EVAN'

describe 'ParticipantsTextField', ->
  beforeEach ->
    @propChange = jasmine.createSpy('change')

    @fieldName = 'to'
    @tabIndex = '100'
    @participants =
      to: [participant1, participant2]
      cc: [participant3]
      bcc: []

    @renderedField = ReactTestUtils.renderIntoDocument(
      <ParticipantsTextField
        field={@fieldName}
        tabIndex={@tabIndex}
        visible={true}
        participants={@participants}
        change={@propChange} />
    )
    @renderedInput = React.findDOMNode(ReactTestUtils.findRenderedDOMComponentWithTag(@renderedField, 'input'))

    @expectInputToYield = (input, expected) ->
      ReactTestUtils.Simulate.change(@renderedInput, {target: {value: input}})
      ReactTestUtils.Simulate.keyDown(@renderedInput, {key: 'Enter', keyCode: 9})

      reviver = (k,v) ->
        return undefined if k in ["id", "object"]
        return v
      found = @propChange.mostRecentCall.args[0]
      found = JSON.parse(JSON.stringify(found), reviver)
      expected = JSON.parse(JSON.stringify(expected), reviver)
      expect(found).toEqual(expected)

  it 'renders into the document', ->
    expect(ReactTestUtils.isCompositeComponentWithType @renderedField, ParticipantsTextField).toBe(true)

  it 'applies the tabIndex provided to the inner input', ->
    expect(@renderedInput.tabIndex/1).toBe(@tabIndex/1)

  describe "inserting participant text", ->
    it "should fire onChange with an updated participants hash", ->
      @expectInputToYield 'abc@abc.com',
        to: [participant1, participant2, new Contact(name: 'abc@abc.com', email: 'abc@abc.com')]
        cc: [participant3]
        bcc: []

    it "should remove added participants from other fields", ->
      @expectInputToYield participant3.email,
        to: [participant1, participant2, new Contact(name: participant3.email, email: participant3.email)]
        cc: []
        bcc: []

    it "should use the name of an existing contact in the ContactStore if possible", ->
      spyOn(ContactStore, 'searchContacts').andCallFake (val, options) ->
        return [participant3] if val is participant3.email
        return []

      @expectInputToYield participant3.email,
        to: [participant1, participant2, participant3]
        cc: []
        bcc: []

    it "should not allow the same contact to appear multiple times", ->
      spyOn(ContactStore, 'searchContacts').andCallFake (val, options) ->
        return [participant2] if val is participant2.email
        return []

      @expectInputToYield participant2.email,
        to: [participant1, participant2]
        cc: [participant3]
        bcc: []

    describe "when text contains Name (Email) formatted data", ->
      it "should correctly parse it into named Contact objects", ->
        newContact1 = new Contact(name:'Ben Imposter', email:'imposter@nylas.com')
        newContact2 = new Contact(name:'Nylas Team', email:'feedback@nylas.com')

        inputs = [
          "Ben Imposter <imposter@nylas.com>, Nylas Team <feedback@nylas.com>",
          "\n\nbla\nBen Imposter (imposter@nylas.com), Nylas Team (feedback@nylas.com)",
          "Hello world! I like cheese. \rBen Imposter (imposter@nylas.com)\nNylas Team (feedback@nylas.com)",
          "Ben Imposter<imposter@nylas.com>Nylas Team (feedback@nylas.com)"
        ]

        for input in inputs
          @expectInputToYield input,
            to: [participant1, participant2, newContact1, newContact2]
            cc: [participant3]
            bcc: []

    describe "when text contains emails mixed with garbage text", ->
      it "should still parse out emails into Contact objects", ->
        newContact1 = new Contact(name:'garbage-man@nylas.com', email:'garbage-man@nylas.com')
        newContact2 = new Contact(name:'recycling-guy@nylas.com', email:'recycling-guy@nylas.com')

        inputs = [
          "Hello world I real. \n asd. garbage-man@nylas.com—he's cool Also 'recycling-guy@nylas.com'!",
          "garbage-man@nylas.com|recycling-guy@nylas.com",
          "garbage-man@nylas.com1WHOA I REALLY HATE DATA,recycling-guy@nylas.com",
          "nils.com garbage-man@nylas.com @nylas.com nope@.com nope!recycling-guy@nylas.com HOLLA AT recycling-guy@nylas."
        ]

        for input in inputs
          @expectInputToYield input,
            to: [participant1, participant2, newContact1, newContact2]
            cc: [participant3]
            bcc: []
