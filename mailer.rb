require 'pony'
require './secrets'

class Mailer
	def initialize
	end

	def send_mail(to: '', subject: '', body: '')
		Pony.mail({
		  :to => to,
		  :via => :smtp,
		  :subject => subject,
		  :body => body,
		  :via_options => {
		    :address              => 'smtp.gmail.com',
		    :port                 => '587',
		    :enable_starttls_auto => true,
		    :user_name            => Secrets.gmail_username,
		    :password             => Secrets.gmail_password,
		    :authentication       => :plain, # :plain, :login, :cram_md5, no auth by default
		    :domain               => "localhost:3000" # the HELO domain provided by the client to the server
		  }
		})
	end

	def send_text(text: '')
		Pony.mail({
		  :to => Secrets.carrier_email,
		  :via => :smtp,
		  :body => text,
		  :via_options => {
		    :address              => 'smtp.gmail.com',
		    :port                 => '587',
		    :enable_starttls_auto => true,
		    :user_name            => Secrets.gmail_username,
		    :password             => Secrets.gmail_password,
		    :authentication       => :plain, # :plain, :login, :cram_md5, no auth by default
		    :domain               => "localhost:3000" # the HELO domain provided by the client to the server
		  }
		})
	end
end