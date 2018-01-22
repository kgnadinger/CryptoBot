Dir["./models/*.rb"].each {|file| require file }
require('./bot')

class BackTester

	def initialize(coin_array: [])
		@trading_fee = 0.0005
		@percentage_to_buy_with = 0.05
		@percentage_to_sell_with = 0.10
		@calculating_length = 500
		@tolerance = 2
		@sell_zone = 70
		@price_multiplier = 1.3
		@stop_loss_percentage = 0.01
		@coin_array = coin_array
	end

	def calibrate
		increase = 1
		stop_loss_percentage = @stop_loss_percentage
		(1..3).each do |t|
			amount = self.go
			if amount > increase
				increase = amount
				stop_loss_percentage
			end
			puts "Amount: #{increase}, Stop Loss Percentage: #{@stop_loss_percentage}"
			@stop_loss_percentage += 0.01
		end
		puts "Final Amount: #{increase}, Price Multiplier: #{stop_loss_percentage}"
	end

	def go
		# starting ven
		ven_amount = 0

		# starting eth
		eth_amount = 1

		# going to buy with 10% of the amount of eth left
		eth_trading_chunks = eth_amount * @percentage_to_buy_with

		# Grab all VenEth, ordered from smallest opening_time(integer)
		venEthArray = @coin_array

		recently_bought = false
		recently_bought_price = 0.0
		recently_bought_index = 1

		venEthArray.each_with_index do |ven_eth, index|
			# starting at 34 because that's how much price data I need to use the indicators
			ven_trading_chunks = ven_amount * @percentage_to_sell_with
			if index > 34
				price_history = venEthArray[0, index + 1].map { |eth| eth.closing_price }

				if price_history.count > 251
					price_history = price_history[index - 250, index]
				end
				algorithm = RsiMacdAlgorithm.new rsiTolerance: 10, price_history: price_history
				
				if algorithm.analyze == "buy"
					# make sure I have enough eth to buy with
					if eth_amount - eth_trading_chunks > 0

						# "withdraw" the eth that I'm buying with
						eth_amount = eth_amount - eth_trading_chunks

						# amount of ven I'm gaining = amount of eth I'm buying with / price all times 0.0095 which is the amount with the fee taken out
						new_ven = (eth_trading_chunks / ven_eth[:closing_price]) * (1 - @trading_fee)
						ven_amount += new_ven
						recently_bought = true
						recently_bought_price = ven_eth[:closing_price]
						puts "New Fun Amount: #{ven_amount}, Price: #{ven_amount * ven_eth[:closing_price]}, Index: #{index}"
					else
						puts "Ran out of Eth"
					end
				elsif recently_bought
					if ven_eth[:closing_price] > recently_bought_price * @price_multiplier
						recently_bought = false
						sell_amount = ven_amount.floor * ven_eth[:closing_price]
						new_eth = sell_amount * (1 - @trading_fee)
						eth_amount += new_eth
						puts "New Eth Amount: #{eth_amount}, Price: #{ven_eth[:closing_price]}, Index: #{index}"
					elsif index - recently_bought_index > 5
						if ven_eth[:closing_price] < recently_bought_price * @stop_loss_percentage
							# "withdraw" the ven I'm selling
							ven_amount = ven_amount - ven_trading_chunks.floor

							# price of ven I'm selling in terms of eth
							sell_amount = ven_trading_chunks.floor * ven_eth[:closing_price]

							# take out the fee
							new_eth = sell_amount * (1 - @trading_fee)
							eth_amount += new_eth
							recently_bought = false
						end
					end				
				elsif algorithm.analyze == "sell"
					# puts "Selling - RSI: buy: #{rsiAlert[:buy]}, sell: #{rsiAlert[:sell]}"
					if ven_amount - ven_trading_chunks.floor > 0

						# "withdraw" the ven I'm selling
						ven_amount = ven_amount - ven_trading_chunks.floor

						# price of ven I'm selling in terms of eth
						sell_amount = ven_trading_chunks.floor * ven_eth[:closing_price]

						# take out the fee
						new_eth = sell_amount * (1 - @trading_fee)
						eth_amount += new_eth
						recently_bought = false
						puts "New Eth Amount: #{eth_amount}, Price: #{ven_eth[:closing_price]}, Index: #{index}"
					else
						puts "Ran out of VEN"
					end
				end
			end
		end
		puts "Ven Amount = #{ven_amount}, Price in Eth = #{ven_amount * venEthArray.last[:closing_price]}"
		puts "Eth Amount = #{eth_amount}}"
		full_amount = (ven_amount * venEthArray.last[:closing_price]) + eth_amount
		puts "Increase/Decrease = #{((full_amount - 1) * 100) / (venEthArray.count * 5 / 60 / 24)}%"
		full_amount
		
	end
	
end