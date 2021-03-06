# This regular expression is used for splitting a string into wrappable words
WORD_RE = /([^ ,\/!.?:;\-\n]+[ ,\/!.?:;\-]*)|\n/g

module.exports = 
    initText: ->
        # Current coordinates
        @x = 0
        @y = 0
        @_lineGap = 0
        
        # Keeps track of what has been set in the document
        @_textState = 
            font: null
            fontSize: null
            mode: 0
            wordSpacing: 0
            
        # state of the wrapping algorithm
        @_wrapState = {}
        
    lineGap: (@_lineGap) ->
        return this
        
    text: (text, x = {}, y, options = {}) ->
        if typeof x is 'object'
            options = x
            x = null
        
        # Update the current position    
        @x = x or options.x or @x
        @y = y or options.y or @y
        
        # add current font to page if necessary
        @page.fonts[@_font.id] ?= @_font.ref
        
        # word wrapping
        if options.width
            @_wrap text, options
        
        # newlines    
        else if (matches = text.split '\n').length > 1
            @_line match, options for match in matches
        
        # single line    
        else
            @_line text, options
            
        return this
        
    moveDown: (lines = 1) ->
        @y += @currentLineHeight(true) * lines + @_lineGap
        return this

    moveUp: (lines = 1) ->
        @y -= @currentLineHeight(true) * lines + @_lineGap
        return this

    list: (array, @x, @y) ->
        gap = Math.round (@_font.ascender / 1000 * @_fontSize) / 2

        for item in array
            @circle x + 3, @y + gap + 3, 3
            @text item, x + 15
            @y += 3

        @fill()
        
    _escape: (text) ->
        ('' + text)
            .replace(/\\/g, '\\\\\\\\')
            .replace(/\(/g, '\\(')
            .replace(/\)/g, '\\)')
            .replace(/&lt;/g, '<')
            .replace(/&gt;/g, '>')
            .replace(/&amp;/g, '&')
            
    _line: (text, options) ->
        wrap = @_wrapState
        paragraphGap = (wrap.firstLine and not wrap.firstParagraph and options.paragraphGap) or 0
        lineGap = options.lineGap or @_lineGap or 0
        
        @_fragment text, @x, @y + paragraphGap, options
        @y += @currentLineHeight(true) + lineGap + paragraphGap
            
    _fragment: (text, x, y, options = {}) ->
        state = @_textState
        wrap = @_wrapState
        align = options.align or 'left'
        text = '' + text
        indent = (wrap.firstLine and options.indent) or 0
        wordSpacing = 0
        
        # text alignments
        if options.width
            lineWidth = options.width - indent
            
            switch align
                when 'right'
                    x += lineWidth - @widthOfString(text)
                
                when 'center'
                    x += lineWidth / 2 - @widthOfString(text) / 2
                
                when 'justify'
                    # don't justify the last line of paragraphs
                    break if wrap.lastLine
                    
                    # split the line into words
                    words = text.match(WORD_RE)
                    break unless words
                     
                    # calculate the word spacing value                
                    textWidth = @widthOfString text.replace(/\s+/g, '')
                    wordSpacing = (lineWidth - textWidth) / (words.length - 1) - @widthOfString(' ')
                    
                    # Remove double spaces
                    text = text.replace(/\s+/g, ' ')
                    
        # indentation support
        x += indent
        
        # flip coordinate system
        y = @page.height - y - (@_font.ascender / 1000 * @_fontSize)
        
        # escape the text for inclusion in PDF
        text = @_escape text
        
        # begin the text object
        @addContent "BT"
        
        # text position
        @addContent "#{x} #{y} Td"
        
        # font and font size
        @addContent "/#{@_font.id} #{@_fontSize} Tf"# unless @_font is state.font and @_fontSize is state.fontSize
        
        # rendering mode
        mode = if options.fill and options.stroke then 2 else if options.stroke then 1 else 0
        @addContent "#{mode} Tr" unless mode is state.mode
        
        # Word spacing
        @addContent wordSpacing + ' Tw' unless wordSpacing is state.wordSpacing
        
        # add the actual text
        @addContent "(#{text}) Tj"
        
        # end the text object
        @addContent "ET"
        
        # keep track of text states
        state.font = @_font
        state.fontSize = @_fontSize
        state.mode = mode
        state.wordSpacing = wordSpacing

    _wrap: (text, options) ->
        wrap = @_wrapState
        lineWidth = options.width
        maxY = @y + options.height
        width = @widthOfString.bind this
        indent = options.indent or 0
        
        # initial settings
        wrap.firstLine = true
        wrap.firstParagraph = true
        
        # split the line into words
        words = text.match(WORD_RE)
        
        # space left on the line to fill with words
        spaceLeft = lineWidth - (options.indent or 0)
        
        # word width cache
        wordWidths = {}
        len = words.length
        buffer = ''
        
        for word, i in words
            w = wordWidths[word] ?= width(word)
            
            if w > spaceLeft or word is '\n'
                # keep track of the wrapping state
                if wrap.lastLine
                    wrap.firstParagraph = false
                    wrap.firstLine = true
                    wrap.lastLine = false
                
                # if we've got a newline, mark it
                if word is '\n'
                    wrap.lastLine = true
                    w += indent
                
                # render the line
                lastLine = buffer.trim()
                @_line lastLine, options
                
                # we're no longer on the first line...
                wrap.firstLine = false
                
                # if we've reached the maximum height provided, don't render any more
                return if @y > maxY
                
                # reset the space left and buffer
                spaceLeft = lineWidth - w
                buffer = if word is '\n' then '' else word

            else
                # add the word to the buffer
                spaceLeft -= w
                buffer += word

        # add the last line
        wrap.lastLine = true
        @_line buffer.trim(), options
        
        # reset wrap state
        @_wrapState = {}