class MailgunApi
  include HTTParty

  class RouteAlreadyExists < StandardError; end
  class Forbidden < StandardError; end
  class KeyMissing < StandardError; end

  def initialize(key)
    @key = key
    fail KeyMissing if @key.blank?
  end

  def show_routes(skip: 0, limit: 1)
    get(
      'https://api.mailgun.net/v2/routes',
      basic_auth: {
        username: 'api',
        password: @key
      },
      params: {
        skip: skip,
        limit: limit
      }
    )
  end

  def create_catch_all
    routes = show_routes(limit: 100)
    if routes.to_s == 'Forbidden'
      { 'message' => 'apikey' }
    else
      if matching_routes(routes).any?
        fail RouteAlreadyExists
      else
        post(
          'https://api.mailgun.net/v2/routes',
          basic_auth: { username: 'api', password: @key },
          body: build_data
        )
        true
      end
    end
  end

  private

  def get(*args)
    response = self.class.get(*args)
    fail Forbidden if response.code == 401
    response
  end

  def post(*args)
    response = self.class.post(*args)
    fail Forbidden if response.code == 401
    response
  end

  def matching_routes(routes)
    match = []
    routes['items'].each do |item|
      next if item['description'] != 'Catch All Route - Created By OneBody'
      next if item['expression'] != "match_recipient('.*@#{Site.current.email_host}')"
      match << item
    end
  end

  def build_data
    {
      priority: 0,
      description: 'Catch All Route - Created By OneBody',
      expression: "match_recipient('.*@#{Site.current.email_host}')",
      action: ["forward('http://#{Site.current.host}/emails.mime')", 'stop()']
    }
  end
end
