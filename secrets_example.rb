class SecretsExample

	def self.api_key
		'<binance api key>'
	end
	
	def self.secret_key
		'<binance secret key'
	end
	
	def self.database_username
		'<database username>'
	end
	
	def self.database_password
		'<database username>'
	end

	def self.gmail_username
		# this is for text messages
		# go to https://www.google.com/settings/security/lesssecureapps to allow your computer to send emails through your gmail
		'<username@gmail.com>'
	end

	def self.gmail_password
		'<gmail password>'
	end

	def self.carrier_email
		# this is for verizon, you'll need to get your carriers email forward to text address
		'<phone number>@vtext.com'
	end
end