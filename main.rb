require 'bot'

bot = BinanceBot.new
raw_price_history = bot.price_history("WTCETH", '5m', 500)
price_history = raw_price_history.map { |p| p[:close] }


data = Indicators::Data.new(price_history)

rsi = data.calc(:type => :rsi, :params => 14).output
macdArray = data.calc(:type => :macd, :params => [12, 26, 9]).output


macdArray.each_with_index do |macd, index|
	if macd && index > 26
		firstMacd = macdArray[index - 1][0] * 1000
		nextMacd = macd[0] * 1000
		# puts "#{firstMacd} #{nextMacd}"
		if ((firstMacd / nextMacd) < 0) && bot.rsi_recently_crossed_threshold(rsi, index)
			puts "MACD: [#{macdArray[index - 1][0]}, #{macd[0]}], Price: #{price_history[index]}, RSI: #{rsi[index]}}"
		end
	end
end