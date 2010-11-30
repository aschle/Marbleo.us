## @constant ###
MOD = 1
## @constant ###
BLOCK_SIZE         = Math.floor(101 * MOD)
## @constant ###
BLOCK_SIZE_HALF    = Math.floor(BLOCK_SIZE / 2)
## @constant ###
BLOCK_SIZE_QUARTER = Math.floor(BLOCK_SIZE_HALF / 2)
## @constant ###
CANVAS_HEIGHT      = 8 * BLOCK_SIZE
## @constant ###
CANVAS_WIDTH       = 7 * BLOCK_SIZE

## @constant ###
TEXTURE_FILE       = '/img/textures.png'
## @constant ###
TEXTURE_BLOCK_SIZE = 101

Cutouts =
  'straight':          [0, 180]
  'curve':             [0,  90]
  'crossing': [0, 90, 180, 270]

class Renderer
  _supportedTextures:
    #texture group:
    #  name: number of rotations/variations
    'basic':
      'solid':           1
      'backside':        1
      'outline':         1
      'cutout':          2
    'top':
      'curve':           4
      'straight':        2
      'crossing':        1
      'crossing-hole':   1
    'middle':
      'curve':           4
      'straight':        2
      'dive':            4

  constructor: (@map, canvasID, @onload) ->
    @canvas = $(canvasID)
    @canvas.attr "width",   CANVAS_WIDTH
    @canvas.attr "height", CANVAS_HEIGHT
    @context = @canvas.get(0).getContext "2d"

    # Load all textures from the texture file
    @textures = {}

    onloadCallback = =>
      @setupTextures(textureFile)
      @setupCaches()
      return @onload()

    textureFile = new Image
    textureFile.onload = onloadCallback
    textureFile.src = TEXTURE_FILE

  # Sets up multiple caches to accelerate the rendering of the blocks and
  # block columns
  setupCaches: ->
    ## @constant ###
    @Cache = {}

  setupTextures: (textureFile) ->
    textureOffset = 0
    for textureGroup, textureDescription of @_supportedTextures
      for texture, rotationsCount of textureDescription
        console.log "loading #{textureGroup}.#{texture}" if DEBUG

        @textures[textureGroup] ?= {}
        @textures[textureGroup][texture] = new Array rotationsCount
        for rotation in [0...rotationsCount]
          canvas = document.createElement 'canvas'
          canvas.width  = BLOCK_SIZE
          canvas.height = BLOCK_SIZE
          context = canvas.getContext '2d'
          try
            context.drawImage textureFile,
                              rotation * TEXTURE_BLOCK_SIZE, textureOffset * TEXTURE_BLOCK_SIZE, TEXTURE_BLOCK_SIZE, TEXTURE_BLOCK_SIZE
                                                          0,                                  0,         BLOCK_SIZE,         BLOCK_SIZE
          catch error
            if DEBUG
              console.log "Encountered error #{error} while loading texture: #{texture}"
              console.log "Texture file may be too small" if error.name is "INDEX_SIZE_ERR"
            break

          @textures[textureGroup][texture][rotation] = canvas
        textureOffset++

  # Calculates the point of origin of the square that the textures get
  # rendered in.
  # Please note that this position lies not in the block in terms of
  # hit-testing
  #
  # Relative to the point of origin of the canvas
  renderingCoordinatesForBlock: (x,y,z) ->
    screenX = (x + y) * BLOCK_SIZE_HALF
    screenY = CANVAS_HEIGHT - 3 * BLOCK_SIZE_QUARTER - (2 * z + x - y + @map.size) * BLOCK_SIZE_QUARTER

    [screenX, screenY]

  # Please note that x and y must be relative to the point of origin of the
  # canvas
  blockAtScreenCoordinates: (x, y) ->
    # Brute force at O(n^3) seems fast enough here
    for blockX in [0...@map.size]
      for blockY in [@map.size - 1..0]
        for blockZ in [@map.size - 1..0]
          continue unless currentBlock = @map.getBlock blockX, blockY, blockZ
          [screenX, screenY] = @renderingCoordinatesForBlock blockX, blockY, blockZ

          # TODO: There seems to be a minor difference on Safari – investigate
          if screenX <= x < (screenX + BLOCK_SIZE) and screenY <= y < (screenY + BLOCK_SIZE)
            pixel = @getTexture('basic','solid').getContext('2d').getImageData x - screenX, y - screenY, 1, 1
            return currentBlock if pixel.data[3] > 0

    return null

  getTexture: (group, type, rotation) ->
    unless rotation
      return @textures[group][type][0] if @_supportedTextures[group][type]?

    rotationCount = @_supportedTextures[group][type]
    return null unless rotationCount?
    return @textures[group][type][rotation / 90 % rotationCount]

  drawMap: ->
    return if @isDrawing or not @map.needsRedraw
    console.time "draw" if DEBUG
    @isDrawing = yes
    @context.clearRect(0, 0, CANVAS_WIDTH, CANVAS_HEIGHT)
    @map.visibleBlocksEach (block, x, y, z) =>
      @drawBlock(block, x, y, z) if block

    @map.setNeedsRedraw no
    @isDrawing = no
    console.timeEnd "draw" if DEBUG

  drawBlock: (block, x, y, z) ->
    [screenX, screenY] = @renderingCoordinatesForBlock x, y, z

    cache_key = "#{block.properties.top            || 'none'}:" +
                "#{block.properties.topRotation    || 'none'}:" +
                "#{block.properties.middle         || 'none'}:" +
                "#{block.properties.middleRotation || 'none'}:" +
                "#{block.properties.low            || 'none'}:" +
                "#{block.properties.lowRotation    || 'none'}:" +
                "#{block == @map.selectedBlock}:"

    unless cached = @Cache[cache_key]
      @Cache[cache_key] = cached = document.createElement 'canvas'
      cached.height = cached.width = BLOCK_SIZE
      buffer = cached.getContext "2d"

      unless block == @map.selectedBlock
        solid = @getTexture 'basic', 'solid'
        buffer.drawImage solid, 0, 0, BLOCK_SIZE, BLOCK_SIZE
      else
        backside = @getTexture 'basic', 'backside'
        buffer.drawImage backside, 0, 0, BLOCK_SIZE, BLOCK_SIZE

        if block.properties.low?
          low_texture = @getTexture 'low', block.properties.low, block.properties.lowRotation
          if low_texture?
            buffer.drawImage low_texture, 0, 0, BLOCK_SIZE, BLOCK_SIZE

        if block.properties.middle?
          mid_texture = @getTexture 'middle', block.properties.middle, block.properties.middleRotation
          if mid_texture?
            buffer.drawImage mid_texture, 0, 0, BLOCK_SIZE, BLOCK_SIZE

      if block.properties.top?
        top_texture = @getTexture 'top', block.properties.top, block.properties.topRotation
        if top_texture?
          buffer.drawImage top_texture, 0, 0, BLOCK_SIZE, BLOCK_SIZE

        cutouts = Cutouts[block.properties.top];

        # TODO: This operation is pretty expensive.
        if cutouts?
          buffer.globalCompositeOperation = 'destination-out'

          for pos in cutouts
            if pos + block.properties.topRotation % 360 == 180
              cutout180 = @getTexture 'basic', 'cutout', 180
              buffer.drawImage cutout180, 0, 0, BLOCK_SIZE, BLOCK_SIZE
            else if pos + block.properties.topRotation % 360 == 270
              cutout270 = @getTexture 'basic', 'cutout', 270
              buffer.drawImage cutout270, 0, 0, BLOCK_SIZE, BLOCK_SIZE

          buffer.globalCompositeOperation = 'source-over'

      @drawOutline buffer, 0, 0

    @context.drawImage cached, screenX, screenY, BLOCK_SIZE, BLOCK_SIZE

  # TODO: Add color support
  drawOutline: (context, x, y, color) ->
    context.drawImage @getTexture('basic','outline'), x, y, BLOCK_SIZE, BLOCK_SIZE