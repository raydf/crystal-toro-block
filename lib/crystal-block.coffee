{CompositeDisposable, Point} = require 'atom'
_ = null
CrystalBlockView = null

module.exports = CrystalBlock =
  config:
    showBottomPanel:
      type: 'boolean'
      default: true
    highlightLine:
      type: 'boolean'
      default: true
    highlightLineNumber:
      type: 'boolean'
      default: false


  crystalBlockView: null
  modalPanel: null
  crystalRootScope: 'source.crystal'

  crystalStartBlockNames: [
    'for'
    'if'
    'unless'
    'until'
    'while'
    'class'
    'module'
    'case'
    'def'
    'begin'
    'describe'
    'context',
    'on',
    'get',
    'post',
    'put',
    'patch'
  ]
  crystalStartBlockScopes: [
     'keyword.control.crystal'
     'keyword.control.start-block.crystal'
     'keyword.control.class.crystal'
     'keyword.control.module.crystal'
     'keyword.control.def.crystal'
     'meta.rspec.behaviour'
  ]

  crystalWhileBlockName: 'while'
  crystalDoBlockName: 'do'
  crystalEndBlockName: 'end'

  crystalKeywordControlScope: 'keyword.control.crystal'
  crystalKeywordControlNames: [
    'end'
    'elsif'
    'else'
    'when'
    'rescue'
    'ensure'
  ]

  crystalDoScope: 'keyword.control.start-block.crystal'

  endBlockStack: []

  activate: ->

    # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    @activeItemSubscription = atom.workspace.observeActivePaneItem( => @subscribeToActiveTextEditor())

  deactivate: ->
    @marker?.destroy()
    @marker = null
    @modalPanel?.destroy()
    @modalPanel = null
    @activeItemSubscription?.dispose()
    @activeItemSubscription = null
    @editorSubscriptions?.dispose()
    @editorSubscriptions = null
    @crystalBlockView?.destroy()
    @crystalBlockView = null

  init: ->
    @loadClasses() unless CrystalBlockView and _
    @crystalBlockView = new CrystalBlockView
    @modalPanel = atom.workspace.addBottomPanel(item: @crystalBlockView.getElement(), visible: false, priority: 500)

  getActiveTextEditor: ->
    atom.workspace.getActiveTextEditor()

  goToMatchingLine: ->
    return atom.beep() unless @blockStartedRowNumber?
    editor = @getActiveTextEditor()
    row = editor.lineTextForBufferRow(@blockStartedRowNumber)
    firstCharPoint = row.search(/\S/)
    editor.setCursorBufferPosition([@blockStartedRowNumber, firstCharPoint])

  subscribeToActiveTextEditor: ->
    @marker?.destroy()
    @modalPanel.hide() if @modalPanel?.isVisible()

    @editorSubscriptions?.dispose()
    editor = @getActiveTextEditor()

    return unless editor?
    return if editor.getRootScopeDescriptor().scopes[0].indexOf(@crystalRootScope) is -1

    @init() unless @crystalBlockView?

    editorElement = atom.views.getView(editor)
    @editorSubscriptions = new CompositeDisposable

    @editorSubscriptions.add atom.commands.add(editorElement,
      'crystal-block:go-to-matching-line': =>
        @goToMatchingLine()
    )

    # @editorSubscriptions.add(editor.onDidChangeCursorPosition(@debouncedCursorChangedCallback))
    @editorSubscriptions.add(editor.onDidChangeCursorPosition(_.debounce( =>
      return unless @getActiveTextEditor() is editor
      @blockStartedRowNumber = null
      @modalPanel.hide() if @modalPanel.isVisible()
      @marker?.destroy()
      @searchForBlock()
    , 100)))

    @searchForBlock()

  searchForBlock: ->
    editor = @getActiveTextEditor()
    grammar = editor.getGrammar()
    cursor = editor.getLastCursor()
    currentRowNumber = cursor.getBufferRow()

    # scope and word matches 'end'
    return if cursor.getScopeDescriptor().scopes.indexOf(@crystalKeywordControlScope) is -1 or
              @crystalKeywordControlNames.indexOf(editor.getWordUnderCursor()) is -1

    @endBlockStack.push(editor.getWordUnderCursor)

    # iterate lines above the cursor
    for rowNumber in [cursor.getBufferRow()..0]
      continue if editor.isBufferRowCommented(rowNumber)

      if rowNumber is currentRowNumber
        prevWordBoundaryPos = cursor.getPreviousWordBoundaryBufferPosition()
        row = editor.getTextInBufferRange([[rowNumber, 0], prevWordBoundaryPos])
      else
        row = editor.lineTextForBufferRow(rowNumber)

      tokens = grammar.tokenizeLine(row).tokens
      filteredTokens = (token for token,i in tokens when !token.value.match /^\s*$/)

      startBlock = (token for token in filteredTokens when token.scopes.indexOf(@crystalDoScope) >= 0)
      if startBlock.length > 0
        if token.value isnt @crystalDoBlockName or
           filteredTokens[0].value isnt @crystalWhileBlockName
          @endBlockStack.pop()
        if @endBlockStack.length is 0
          return @highlightBlock(rowNumber)

      for token in filteredTokens by -1
        for scope in token.scopes
          if scope is @crystalKeywordControlScope and token.value is @crystalEndBlockName
            @endBlockStack.push(scope.value)
          else if @crystalStartBlockScopes.indexOf(scope) >= 0 and
                  @crystalStartBlockNames.indexOf(token.value) >= 0
            # Support assigning variable with a case statement
            # e.g.
            # var = case cond
            #       when 1 then 10
            #       end
            if token.value is 'case'
              @endBlockStack.pop()
            else
              for firstTokenScope in filteredTokens[0].scopes
                if @crystalStartBlockScopes.indexOf(firstTokenScope) >= 0 and
                   @crystalStartBlockNames.indexOf(filteredTokens[0].value) >= 0
                  @endBlockStack.pop()
                  break

            if @endBlockStack.length is 0
              return @highlightBlock(rowNumber)

  highlightBlock: (rowNumber)->
    editor = @getActiveTextEditor()
    row = editor.lineTextForBufferRow(rowNumber)
    firstCharPoint = row.search(/\S/)
    @marker = editor.markBufferRange([[rowNumber, firstCharPoint], [rowNumber, row.length]])

    @blockStartedRowNumber = rowNumber
    if atom.config.get('crystal-block.highlightLine')
      editor.decorateMarker(@marker, {type: 'highlight', class: 'crystal-block-highlight'})
    if atom.config.get('crystal-block.highlightLineNumber')
      editor.decorateMarker(@marker, {type: 'line-number', class: 'crystal-block-highlight'})
    if atom.config.get('crystal-block.showBottomPanel')
      @crystalBlockView.updateMessage(rowNumber)
      @modalPanel.show()

  loadClasses: ->
    _ = require 'underscore-plus'
    CrystalBlockView = require './crystal-block-view'
