Dir["./models/*.rb"].each {|file| require file }
require('./bot')

class BackTester

	def initialize
		@trading_fee = 0.0005
		@percentage_to_buy_with = 0.05
		@percentage_to_sell_with = 0.10
		@calculating_length = 500
		@tolerance = 2
		@sell_zone = 70
		@price_multiplier = 1.3
	end

	def calibrate
		increase = 1
		percentage = @percentage_to_sell_with
		(1..10).each do |t|
			amount = self.go
			if amount > increase
				increase = amount
			end
			puts "Amount: #{increase}, Price Multiplier: #{@price_multiplier}"
			@price_multiplier += 0.1
		end
		puts "Final Amount: #{increase}, Price Multiplier: #{@price_multiplier}"
	end

	def go
		# starting ven
		ven_amount = 0

		# starting eth
		eth_amount = 100

		# going to buy with 10% of the amount of eth left
		eth_trading_chunks = eth_amount * @percentage_to_buy_with

		# Grab all VenEth, ordered from smallest opening_time(integer)
		venEthArray = EthUsdt.order(:opening_time).select(:id, :closing_price).all

		recently_bought = false
		recently_bought_price = 0.0

		venEthArray.each_with_index do |ven_eth, index|
			# starting at 34 because that's how much price data I need to use the indicators
			if index > 34

				# going to sell 10% of my ven
				ven_trading_chunks = ven_amount * @percentage_to_sell_with

				# array of prices up to the index
				price_history = venEthArray[0, index + 1].map { |eth| eth.closing_price }

				# optomization, only going to calculate indicators with 500 points of price history
				if price_history.count > 251
					price_history = price_history[index - 250, index]
				end


				data = Indicators::Data.new(price_history)

				# calculate rsi
				rsi = data.calc(:type => :rsi, :params => 14).output

				# calculate MACD
				macdArray = data.calc(:type => :macd, :params => [12, 26, 9]).output

				algorithm = RsiMacdAlgorithm.new(rsiTolerance: @tolerance)

				# reference to rsi so I know whether to buy or sell
				rsiAlert = algorithm.rsi_recently_crossed_threshold?(rsi, index)

				# test to see if rsi went to the buy/sell zones and a macd cross
				if algorithm.macd_recently_crossed?(macdArray, index) && algorithm.rsiAlert[:crossed]

					# rsi > 70
					if rsiAlert[:buy]
						# make sure I have enough eth to buy with
						puts "Buying - RSI: buy: #{rsiAlert[:buy]}, sell: #{rsiAlert[:sell]}"
						if eth_amount - eth_trading_chunks > 0

							# "withdraw" the eth that I'm buying with
							eth_amount = eth_amount - eth_trading_chunks

							# amount of ven I'm gaining = amount of eth I'm buying with / price all times 0.0095 which is the amount with the fee taken out
							new_ven = (eth_trading_chunks / ven_eth[:closing_price]) * (1 - @trading_fee)
							ven_amount += new_ven
							recently_bought = true
							recently_bought_price = ven_eth[:closing_price]
							puts "New Ven Amount: #{ven_amount}, Price: #{ven_eth[:closing_price] * ven_amount}, Index: #{index}"
						else
							puts "Ran out of Eth"
						end
					# rsi < 30
					elsif recently_bought
						test_price = recently_bought_price * @price_multiplier
						if ven_eth[:closing_price] > test_price
							new_eth = ven_amount * ven_eth[:closing_price] * (1 - @trading_fee)
							ven_amount = 0
							eth_amount += new_eth
							recently_bought = false
							recently_bought_price = 0.0
							puts "sold"
						end
					elsif rsiAlert[:sell]
						puts "Selling - RSI: buy: #{rsiAlert[:buy]}, sell: #{rsiAlert[:sell]}"
						if ven_amount - ven_trading_chunks > 0

							# "withdraw" the ven I'm selling
							ven_amount = ven_amount - ven_trading_chunks

							# price of ven I'm selling in terms of eth
							sell_amount = ven_trading_chunks * ven_eth[:closing_price]

							# take out the fee
							new_eth = sell_amount * (1 - @trading_fee)
							eth_amount += new_eth
							puts "New Eth Amount: #{eth_amount}, Price: #{ven_eth[:closing_price]}, Index: #{index}"
						else
							puts "Ran out of VEN"
						end
					end
				end
			end
		end
		puts "Ven Amount = #{ven_amount}, Price in Eth = #{ven_amount * venEthArray.last[:closing_price]}"
		puts "Eth Amount = #{eth_amount}}"
		full_amount = (ven_amount * venEthArray.last[:closing_price]) + eth_amount
		puts "Increase/Decrease = #{((full_amount - ven_amount) / ven_amount) * 100}%"
		full_amount
		
	end
	
end