# Mix this module into the main application module to provide
# information about the current email configuration
#
# In config/application.rb:
#
#     module OneBody
#       extend EmailConfigInfo
#     end
#
module EmailConfigInfo
  def email_configured?
    smtp_config['address'].present?
  end

  def smtp_config
    return unless File.exist?(email_config_path)
    YAML.load_file(email_config_path).fetch(Rails.env.to_s, {}).fetch('smtp', {})
  end

  def email_config_path
    Rails.root.join('config/email.yml')
  end
end
