require('./ven_eth')
require('./bot')

class BackTester

	def initialize
		@trading_fee = 0.0005
		@percentage_to_buy_with = 0.10
		@percentage_to_sell_with = 0.10
		@calculating_length = 500
	end

	def go
		ven_amount = 0
		eth_amount = 0.01
		eth_trading_chunks = eth_amount * @percentage_to_buy_with
		ven_trading_chunks = ven_amount * @percentage_to_sell_with
		venEthArray = VenEth.order(:opening_time).select(:id, :closing_price).all
		venEthArray.each_with_index do |ven_eth, index|
			if index > 34
				beginning_time = Time.now
				price_history = venEthArray[0, index + 1].map { |eth| eth.closing_price }
				if price_history.count > 501
					puts "chaning price history: #{index}"
					price_history = price_history[index - 500, index]
				end
				data = Indicators::Data.new(price_history)
				rsi = data.calc(:type => :rsi, :params => 14).output
				macdArray = data.calc(:type => :macd, :params => [12, 26, 9]).output
				rsiAlert = rsi_recently_crossed_threshold?(rsi, index)
				if macd_recently_crossed?(macdArray, index) && rsiAlert[:crossed]
					if rsiAlert[:buy]
						if eth_amount - eth_trading_chunks > 0
							eth_amount = eth_amount - eth_trading_chunks
							new_ven = (eth_trading_chunks / ven_eth[:closing_price]) * (1 - @trading_fee)
							ven_amount += new_ven
							puts "New Ven Amount: #{ven_amount}, Price: #{ven_eth[:closing_price] * ven_amount}, Index: #{index}"
						else
							puts "Ran out of Eth"
						end
					elsif rsiAlert[:sell]
						if ven_amount - ven_trading_chunks > 0
							ven_amount = ven_amount - ven_trading_chunks
							sell_amount = ven_amount * ven_eth[:closing_price]
							new_eth = sell_amount * (1 - @trading_fee)
							eth_amount += new_eth
							puts "New Eth Amount: #{eth_amount}, Price: #{ven_eth[:closing_price]}, Index: #{index}"
						else
							puts "Ran out of VEN"
						end
					end
				end
				puts "Time End: #{(Time.now - beginning_time) * 1000} milliseconds, Index: #{index}}"
				beginning_time = Time.now
			end
		end
		puts "Ven Amount = #{ven_amount}, Price in Eth = #{ven_amount * venEthArray.last[:closing_price]}"
		puts "Eth Amount = #{eth_amount}}"
		
	end

	def macd_recently_crossed?(macdArray, index)
		firstMacd = format_number_to_be_larger_than_one(macdArray[macdArray.length - 2][0])
		nextMacd = format_number_to_be_larger_than_one(macdArray[macdArray.length - 1][0])
		if ((firstMacd / nextMacd) < 0)
			true
		else
			false
		end
	end

	def format_number_to_be_larger_than_one(number)
		if (number < 1 && number > 0) || (number < 0 && number > -1)
			number = number * 10
		else
			number
		end
	end

	def rsi_recently_crossed_threshold?(rsiArray, index)
		tolerance = 10
		crossed = false
		buy = false
		sell = false
		rsiArray[(rsiArray.length - 1 - tolerance)..(rsiArray.length - 1)].each do |rsi|
			if rsi > 70
				crossed = true
				sell = true
			elsif rsi < 30
				buy = true
				crossed = true
			end
		end
		{ crossed: crossed, sell: sell, buy: buy }
	end
end