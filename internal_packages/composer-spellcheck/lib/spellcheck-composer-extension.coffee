{ComposerExtension, AccountStore, DOMUtils, NylasSpellchecker} = require 'nylas-exports'
_ = require 'underscore'
remote = require('remote')
MenuItem = remote.require('menu-item')
spellchecker = NylasSpellchecker

SpellcheckCache = {}

class SpellcheckComposerExtension extends ComposerExtension

  @isMisspelled: (word) ->
    SpellcheckCache[word] ?= spellchecker.isMisspelled(word)
    SpellcheckCache[word]

  @onContentChanged: ({editor}) =>
    @walkTree(editor)

  @onShowContextMenu: ({editor, event, menu}) =>
    selection = editor.currentSelection()
    range = DOMUtils.Mutating.getRangeAtAndSelectWord(selection, 0)
    word = range.toString()
    if @isMisspelled(word)
      corrections = spellchecker.getCorrectionsForMisspelling(word)
      if corrections.length > 0
        corrections.forEach (correction) =>
          menu.append(new MenuItem({
            label: correction,
            click: @applyCorrection.bind(@, editor, range, selection, correction)
          }))
      else
        menu.append(new MenuItem({ label: 'No Guesses Found', enabled: false}))

      menu.append(new MenuItem({ type: 'separator' }))
      menu.append(new MenuItem({
        label: 'Learn Spelling',
        click: @learnSpelling.bind(@, editor, word)
      }))
      menu.append(new MenuItem({ type: 'separator' }))

  @applyCorrection: (editor, range, selection, correction) =>
    DOMUtils.Mutating.applyTextInRange(range, selection, correction)
    @walkTree(editor)

  @learnSpelling: (editor, word) =>
    spellchecker.add(word)
    delete SpellcheckCache[word]
    @walkTree(editor)

  @walkTree: (editor) =>
    # Remove all existing spellcheck nodes
    spellingNodes = editor.rootNode.querySelectorAll('spelling')
    for node in spellingNodes
      editor.whilePreservingSelection =>
        DOMUtils.unwrapNode(node)

    # Normalize to make sure words aren't split across text nodes
    editor.rootNode.normalize()

    selection = document.getSelection()
    selectionSnapshot =
      anchorNode: selection.anchorNode
      anchorOffset: selection.anchorOffset
      focusNode: selection.focusNode
      focusOffset: selection.focusOffset
    selectionImpacted = false

    treeWalker = document.createTreeWalker(editor.rootNode, NodeFilter.SHOW_TEXT)
    nodeList = []
    nodeMisspellingsFound = 0

    while (treeWalker.nextNode())
      nodeList.push(treeWalker.currentNode)

    # Note: As a performance optimization, we stop spellchecking after encountering
    # 10 misspelled words. This keeps the runtime of this method bounded!

    while (node = nodeList.shift())
      break if nodeMisspellingsFound > 10
      str = node.textContent

      # https://regex101.com/r/bG5yC4/1
      wordRegexp = /(\w[\w'’-]*\w|\w)/g

      while ((match = wordRegexp.exec(str)) isnt null)
        break if nodeMisspellingsFound > 10
        misspelled = @isMisspelled(match[0])

        if misspelled
          # The insertion point is currently at the end of this misspelled word.
          # Do not mark it until the user types a space or leaves.
          if selectionSnapshot.focusNode is node and selectionSnapshot.focusOffset is match.index + match[0].length
            continue

          if match.index is 0
            matchNode = node
          else
            matchNode = node.splitText(match.index)
          afterMatchNode = matchNode.splitText(match[0].length)

          spellingSpan = document.createElement('spelling')
          spellingSpan.classList.add('misspelled')
          spellingSpan.innerText = match[0]
          matchNode.parentNode.replaceChild(spellingSpan, matchNode)

          for prop in ['anchor', 'focus']
            if selectionSnapshot["#{prop}Node"] is node
              if selectionSnapshot["#{prop}Offset"] > match.index + match[0].length
                selectionImpacted = true
                selectionSnapshot["#{prop}Node"] = afterMatchNode
                selectionSnapshot["#{prop}Offset"] -= match.index + match[0].length
              else if selectionSnapshot["#{prop}Offset"] > match.index
                selectionImpacted = true
                selectionSnapshot["#{prop}Node"] = spellingSpan.childNodes[0]
                selectionSnapshot["#{prop}Offset"] -= match.index

          nodeMisspellingsFound += 1
          nodeList.unshift(afterMatchNode)
          break

    if selectionImpacted
      selection.setBaseAndExtent(selectionSnapshot.anchorNode, selectionSnapshot.anchorOffset, selectionSnapshot.focusNode, selectionSnapshot.focusOffset)

  @finalizeSessionBeforeSending: ({session}) ->
    body = session.draft().body
    clean = body.replace(/<\/?spelling[^>]*>/g, '')
    if body != clean
      return session.changes.add(body: clean)

SpellcheckComposerExtension.SpellcheckCache = SpellcheckCache

module.exports = SpellcheckComposerExtension
