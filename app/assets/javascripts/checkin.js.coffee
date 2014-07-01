#= require sonicnet

class Checkin

  checkedIn: {}
  people: {}

  render: ->
    $('.checkin-select-person').click(@selectPerson).each (i, elm) =>
      id = $(elm).data('id')
      @people[id] = new CheckinPerson($("#person_#{id}"))
    $('#add-a-guest').click(@addGuest)
    $('.checkin-print .btn').click(@print)
    @sp = new SonicProtocol(true)
    @sp.listen()
    @


  selectPerson: (e) =>
    e.preventDefault()
    p.hide() for _, p of @people
    id = $(e.delegateTarget).data('id')
    @people[id].show()

  addGuest: (e) =>
    e.preventDefault()
    alert('NOT YET IMPLEMENTED')

  personCheckedIn: (id, times) =>
    @checkedIn[id] = times
    if times.length > 0
      $('.checkin-print').show().find('.tag-count').text(@tagCount())
    else
      $('.checkin-print').find('.tag-count').text(@tagCount())
      $('.checkin-print').hide() if @tagCount() == 0

  tagCount: =>
    Object.keys(@checkedIn).length

  print: (e) =>
    e.preventDefault()
    $.ajax "/checkin.json",
      data: JSON.stringify(people: @checkedIn)
      contentType: 'application/json; charset=utf-8'
      dataType: 'json'
      method: 'put'
      complete: (resp) =>
        labels = []
        (labels = labels.concat(l)) for _, l of resp.responseJSON.labels
        alert("should print #{labels.length} label(s) - NOT YET IMPLEMENTED")
        location.replace('/checkin')

class CheckinPerson

  constructor: (@elm) ->
    @id = @elm.data('id')
    @button = $(".checkin-select-person[data-id='#{@id}']")
    @times = for time in @elm.find('.checkin-time')
      new CheckinTime($(time), this)
    @elm.find('.same-as-last-week').click(@sameAsLastWeek)

  show: =>
    @elm.show()
    @button.addClass('active')
    t.show() for t in @times

  hide: =>
    @elm.hide()
    t.hide() for t in @times
    @button.removeClass('active')

  sameAsLastWeek: (e) =>
    e.preventDefault()
    alert('NOT YET IMPLEMENTED')

  classSelected: (id) =>
    @elm.find('.checkin-same').hide()
    @selected = true
    @button.find('.status').removeClass('fa-chevron-right').addClass('fa-check text-green')
    checkin.personCheckedIn(@id, (t.selected for t in @times))

  classUnselected: (id) =>
    count = (t for t in @times when t.selected).length
    if count == 0
      @elm.find('.checkin-same').show()
      @selected = false
      @button.find('.status').removeClass('fa-check text-green').addClass('fa-chevron-right')
    checkin.personCheckedIn(@id, (t.selected for t in @times))


class CheckinTime

  selected: null

  constructor: (@elm, @person) ->
    @id = @elm.data('id')
    @elm.find('.checkin-open-section').on 'click', @openSection
    @elm.find('.checkin-select-class').on 'click', @selectClass
    @elm.find('.checkin-close').on 'click', @closeTime
    @elm.find('.checkin-open').on 'click', @openTime
    @elm.find('.checkin-change').on 'click', @clearClassAndOpenTime
    @

  show: =>
    @elm.show()

  hide: =>
    @elm.hide()

  openSection: (e) =>
    e.preventDefault()
    elm = $(e.delegateTarget)
    expanded = elm.hasClass('expanded')
    id = elm.data('id')
    @elm.find('.class-list.indented').hide()
    @elm.find('.checkin-open-section').removeClass('expanded')
    unless expanded
      elm.addClass('expanded')
      $(id).show()

  selectClass: (e) =>
    e.preventDefault()
    elm = $(e.delegateTarget)
    @elm.find('.box-body').hide()
    id = elm.data('id')
    name = elm.find('.name').html()
    @elm.find('.checkin-selection-header').html(
      "<i class='fa fa-check'></i> " +
      name
    )
    @elm.find('.checkin-not-attending-header').hide()
    @elm.addClass('selection-made')
    @elm.find('.checkin-close').hide()
    @elm.find('.checkin-change').show()
    @selected = id
    @person.classSelected(@selected)

  closeTime: (e) =>
    e.preventDefault()
    elm = $(e.delegateTarget)
    @elm.find('.box-body').hide()
    @elm.find('.checkin-close').hide()
    @elm.find('.checkin-open').show()
    @elm.find('.checkin-not-attending-header').show()

  clearClassAndOpenTime: (e) =>
    e.preventDefault()
    elm = $(e.delegateTarget)
    @elm.find('.checkin-selection-header').html('')
    @elm.removeClass('selection-made')
    @elm.find('.checkin-open, .checkin-change').hide()
    @selected = null
    @person.classUnselected(@selected)
    @openTime(e)

  openTime: (e) =>
    e.preventDefault()
    elm = $(e.delegateTarget)
    @elm.find('.box-body').show()
    @elm.find('.checkin-close').show()
    @elm.find('.checkin-open').hide()
    @elm.find('.checkin-not-attending-header').hide()

class SonicProtocol
  constructor: (kiosk) ->
    @audioContext = new webkitAudioContext();
    @alpha = '0123456789.';
    @
  listen: =>
    console.log 'listen'
    @sserver = new SonicServer(alphabet: @alpha)
    @sserver.on 'message', (message) ->
      alert 'Not implimented: Print tags for ' + message.replace(/\./g,'')
    @sserver.start()
  send: (message) =>
    ssocket = new SonicSocket(
      alphabet: @alpha
      charDuration: 0.1
    )
    ssocket.send message.split('').join('.')

checkin = new Checkin().render()
