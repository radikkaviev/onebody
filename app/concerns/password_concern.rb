require 'active_support/concern'

module PasswordConcern
  extend ActiveSupport::Concern

  included do
    attr_accessor :password
    before_save :encrypt_password
  end

  def encrypt_password
    if password.present?
      self.password_salt = BCrypt::Engine.generate_salt
      self.password_hash = BCrypt::Engine.hash_secret(password, password_salt)
      self.encrypted_password = self.salt = nil # remove old password
    end
  end

  module ClassMethods
    def authenticate(email, password)
      people = undeleted.where(email: email.downcase)
      if people.count > 0
        people.each do |person|
          if person.password_hash
            return person if person.password_hash == BCrypt::Engine.hash_secret(password, person.password_salt)
          elsif person.encrypted_password
            if person.encrypted_password == legacy_password_hash(password, person.salt)
              person.password = person.password_confirmation = password
              person.save(validate: false)
              return person
            end
          end
        end
        false
      else
        nil
      end
    end

    def legacy_password_hash(password, salt)
      pass = Digest::MD5.hexdigest(password)
      10.times { pass = Digest::SHA1.hexdigest(pass + salt) }
      pass
    end
  end
end
