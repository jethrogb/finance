#!/usr/bin/env ruby
# encoding: utf-8
#
# Jethro's finance tools
# Copyright (C) 2014  Jethro G. Beekman
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software Foundation,
# Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.

require 'date'
require 'erubis'
require 'ostruct'
Subject=""

if ARGV.length!=3 then
	$stderr.puts "Usage: ruby alexparse.rb <input-pattern> <output-directory> <symbols-file>"
	exit
end

Input=ARGV[0].dup
Output=ARGV[1].dup
Symbols=ARGV[2].dup

def pipeio(cmd)
	IO.popen(cmd+[:in => [Subject]]) { |io| io.read }
end

def parsenum(int,cents=nil)
	int,cents=int.split(',') if cents.nil?
	int||=''
	cents||=''
	return (int.gsub('.','')+'.'+cents).to_r
end

def unused_fields?(hash,*args)
	keys=hash.keys-args
	if keys.length>0 then
		$stderr.puts "Unused fields (#{hash[:type]}): "+(keys.map{|v|v.to_s}*',')
		#$stderr.puts hash.inspect
	end
end

module AlexV1
	#  99       01-01    01-01    Description description description description des               9.999,99             9.999,99
	#......    .......  .......  ............................................................    .................    ...........
	Format_check=/^.{6}[^ ]{4}.{7}[^ ]{2}.{7}[^ ]{2}.{60}[^ ]{4}.{17}[^ ]{4}.*$/
	Format=/^(.{6}) {4}(.{7}) {2}(.{7}) {2}(.{60}) {4}(.{17}) {4}(.*)$/
	Types={
		'Afrekening creditrente'=>:interest,
		'Afrekening debetrente'=>:interest,
		'Deponering'=>:deposit, # for dividends/splits/...?
		'Koop'=>:buystock,
		'Lichting'=>:lift, # lift?? for dividends/splits/...?
		'Overboeking effecten'=>:transferstock,
		'Overboeking geld'=>:transfer,
		'Storno'=>:counterentry,
		'Toekenning dividend'=>:awarddividend,
		'Toekenning claim'=>:awarddividend,
		'Uitkering dividend'=>:distributedividend,
		'Verkoop'=>:sellstock,
		'Verrekening kosten/vergoedingen'=>:fees,
	}
	
	def self.make_longdesc(array)
		(array*' ').gsub(/ +/,' ').strip
	end
	
	def self.fix_currency(trans,st_cur)
		return true unless trans.include? :currency
		tr_cur=trans[:currency]
		return true if tr_cur==st_cur
		if not trans.include? :netvalue then
			$stderr.puts "--#{Subject}--"
			$stderr.puts "AlexV1.fix_currency: no net value: #{trans[:longdesc]}"
			return false
		end
		if not trans.include? :xrate then
			$stderr.puts "--#{Subject}--"
			$stderr.puts "AlexV1.fix_currency: no exchange rate: #{trans[:longdesc]}"
			return false
		end
		xr_cur=trans[:xrate][0]
		if xr_cur!=tr_cur and xr_cur!=st_cur then
			$stderr.puts "--#{Subject}--"
			$stderr.puts "AlexV1.fix_currency: exchange rate currency invalid, transaction #{tr_cur}, statement #{st_cur}, rate #{xr_cur}: #{trans[:longdesc]}"
			return false
		end
		tr_netvalue=trans[:netvalue]
		st_netvalue=trans[:value]
		st_netvalue+=trans[:fees] if trans.include? :fees
		st_netvalue=st_netvalue.abs # take absolute value after adding fees to make addition/substraction work the right way
		c_xrate=tr_netvalue/st_netvalue
		o_xrate=trans[:xrate][1]
		o_xrate=1/o_xrate if xr_cur==st_cur
		if (o_xrate-c_xrate).abs>=0.01 then
			$stderr.puts "--#{Subject}--"
			$stderr.puts "AlexV1.fix_currency: exchange rates don't match, computed #{c_xrate}, statement #{o_xrate}: #{trans[:longdesc]}"
			return false
		end
		trans[:price]/=c_xrate if trans.include? :price
		trans[:xrate]=c_xrate
	end
	
	def self.parse_stock_firstline(line1,line2)
		lines_used=1
		line1=line1.strip
		unless /[0-9]/=~line1[-1] # line wrapped?
			line1+=' '+line2.strip
			lines_used=2
		end

		# For example: NKR 90 Skagen Global Acc (NOK) @ NKR 814,522
		m=/^\s*([A-Z]{3}\s+|\$\s+)?(\d+)\s+(.+?)\s+@\s+([A-Z]{3}\s+|\$\s+)?([0-9.]+,\d{2,})\s*$/.match(line1)
		
		ret=nil
		if m
			ret={}
			unless m[1].nil?
				if m[1].strip==m[4].strip
					ret[:currency]=m[1].strip
				else
					$stderr.puts "--#{Subject}--"
					$stderr.puts "AlexV1.parse_stock_firstline: Currencies don't match for transaction description line: #{line1}"
					return false
				end
			end
			ret[:amount]=m[2].to_i
			ret[:name]=m[3]
			%w(aand. cert dividend share Trackers).each do |prefix|
				ret[:name][0..prefix.length]='' if ret[:name][0..prefix.length]==prefix+' '
			end
			ret[:price]=parsenum(m[5])
		end
		
		return ret,lines_used
	end
	
	def self.parse_stock_metadata(desc,info)
		ret={}
		desc.each do |line|
			if line.strip.length>0 then
				next ret[:netvalue]=parsenum($~[2]) if /^\s*Effectieve waarde:\s+(#{info[:currency]}\s+)?([0-9.]+,\d{2,})/=~line
				next ret[:fees]=parsenum($~[1]) if /^\s*Provisie:\s+([0-9.]+,\d{2,})/=~line
				next ret[:totalpos]=$~[1].to_i if /^\s*Uw positie na deze transactie:\s+(-?\d+)/=~line
				next ret[:onum]=$~[1].to_i if /^\s*Ordernummer\s+(\d+)/=~line
				next ret[:xrate]=[$~[1],parsenum($~[2])] if /^\s*Koers:\s+([A-Z]{3}|\$)\s+@\s+?([0-9.]+,\d{2,})/=~line
				next ret[:reinvestment]=true if /^\s*'Herbelegging'/=~line
				next ret[:sourcetax]=[parsenum($~[1]).to_r/100,parsenum($~[2])] if /^\s*Bronbelasting:\s+([0-9.,]+)\s*%\s+([0-9.]+,\d{2,})/=~line
				next ret[:vat]=parsenum($~[1]) if /^\s*BTW:\s+([0-9.]+,\d{2,})/=~line
				$stderr.puts "--#{Subject}--"
				$stderr.puts "AlexV1.parse_stock_metadata: Unknown transaction description metadata line: #{line.strip}"
				return false
			end
		end
		return ret
	end
	
	def self.parse_stock(desc)
		ret={:exchange=>desc[1].strip}
		
		m,lines_used=parse_stock_firstline(desc[2],desc[3])
		datastart=2+lines_used
		
		unless m
			ret.delete :exchange
			m,lines_used=parse_stock_firstline(desc[1],desc[2])
			datastart=1+lines_used
		end
		
		unless m
			$stderr.puts "--#{Subject}--"
			$stderr.puts "AlexV1.parse_stock: Can't match transaction description line: #{desc[2]}"
			return false
		end
		ret.merge! m

		ret[:longdesc]=make_longdesc(desc[0..0]+desc[(datastart-lines_used)...(datastart)])
		return false unless meta=parse_stock_metadata(desc[datastart..-1],ret)
		ret.merge! meta
		
		return ret
	end
	
	def self.parse_transfer(desc,firstline=1)
		ret={}
		if desc[firstline]=~/^\s*(Naar|Van)\s+([0-9.]+)/ then
			ret[($~[1]=='Van') ? :fromacct : :toacct]=$~[2].gsub('.','')
		elsif desc[firstline]=~/^\s*(Naar|Van)\s+([A-Z]{3}|\$)\s+rekening/ then
			ret[($~[1]=='Van') ? :fromacct : :toacct]=$~[2]
			ret[:currency]=$~[2]
		end
		commentfirst=commentlast=nil
		(firstline...(desc.length)).each do |i|
			commentfirst=i if not commentfirst and desc[i]=~/^\s*'/
			commentlast=i if commentfirst and desc[i]=~/'\s*$/
			break if commentlast
		end
		if commentfirst and commentlast then
			ret[:memo]=desc[commentfirst..commentlast].map{|v|v.strip}.join(' ').match(/^\s*'(.*)'\s*$/)[1]
			firstline=commentlast+1
		end

		cindex=desc[firstline..-1].find_index { |line| /:/=~line }
		if cindex
			ret[:longdesc]=make_longdesc(desc[0...(firstline+cindex)])
			return false unless meta=parse_stock_metadata(desc[(cindex+firstline)..-1],ret)
			ret.merge! meta
		else
			ret[:longdesc]=make_longdesc(desc)
		end
		
		ret.delete :currency if ret[:currency] and not ret[:netvalue]

		return ret
	end
	
	def self.parse_transferstock(desc)
		ret,lines_used=parse_stock_firstline(desc[1],desc[2])
		unless ret
			$stderr.puts "--#{Subject}--"
			$stderr.puts "AlexV1.parse_transferstock: Can't match transaction description line: #{desc[1].strip}"
			return false
		end
		return false unless trans=parse_transfer(desc,1+lines_used)
		ret.merge! trans
		return ret
	end

	def self.parse_trans(buf,info)
		return true if (buf*"\n").strip.length==0
		info[:transactions]||=[]

		val={}
		cols=buf.map { |line| Format.match(line)[1..-1] }.transpose
		{0=>:tnum,1=>:tdate,2=>:idate,4=>:debit,5=>:credit}.each do |col,name|
			val[name]=""
			cols[col].each do |v|
				v.strip!
				if v.length>0 and val[name].length>0
					$stderr.puts "--#{Subject}--"
					$stderr.puts "AlexV1.parse_trans: Multiple values for column #{col}:#{name} for transaction starting with: #{buf.map{|v|v.strip}*' / '}"
					return false
				end
				val[name]+=v
			end
		end
		desc=cols[3]
		
		val[:tnum]=val[:tnum].to_i
		
		val[:tdate]=Date.strptime("#{val[:tdate]}-#{info[:sdate].year}",'%d-%m-%Y')
		
		val[:idate]=Date.strptime("#{val[:idate]}-#{info[:sdate].year}",'%d-%m-%Y')
		
		unless Types.include? desc[0]=desc[0].strip
			$stderr.puts "--#{Subject}--"
			$stderr.puts "AlexV1.parse_trans: Unknown transaction type #{desc[0]} for transaction: #{buf.map{|v|v.strip}*' / '}"
			return false
		end
		
		case val[:type]=Types[desc[0]]
			when :buystock, :sellstock
				return false unless stock=parse_stock(desc)
				if stock[:name]=~/^scrip\s+(\S.*\S)\s+-Right-/ then
					val[:type]=:distributedividend
					stock[:name]=$~[1]
				end
				val.merge! stock
			when :distributedividend
				return false unless stock=parse_stock(desc)
				val.merge! stock
			when :transfer, :interest, :fees
				return false unless trans=parse_transfer(desc)
				val.merge! trans
			when :transferstock
				return false unless trans=parse_transferstock(desc)
				val.merge! trans
			when :deposit, :lift, :awarddividend
				# Ignore
			when :counterentry
				if Types[desc[1].strip]!=:lift then
					$stderr.puts "--#{Subject}--"
					$stderr.puts "AlexV1.parse_trans: Can't handle `#{desc[0]}' of type `#{desc[1].strip}' for transaction: #{buf.map{|v|v.strip}*' / '}"
					return false
				else
					# Ignore
				end
			else
				$stderr.puts "--#{Subject}--"
				$stderr.puts "AlexV1.parse_trans: This should never happen"
				return false
		end
		
		if val[:debit].length>0 and val[:credit].length>0
			$stderr.puts "--#{Subject}--"
			$stderr.puts "AlexV1.parse_trans: Columns `debit' and `credit' both not empty for transaction: #{buf.map{|v|v.strip}*' / '}"
			return false
		end
		val[:value]=parsenum(val[:credit])-parsenum(val[:debit])
		val.delete :credit
		val.delete :debit
		
		return false unless fix_currency val, info[:currency]

		info[:transactions] << val

		return true
	end

	def self.parse
		ret={:bank=>'alex.nl'}
		# Afschriftinfo
		res=pipeio %W(pdftotext -nopgbrk -f 1 -l 1 -fixed 8 -r 150 -x 790 -y 405 -W #{1116-790} -H #{474-405} -layout - -)
		return false unless
			m1=/^\s*(IBAN|Rekeningnummer)\s+(\S+)/.match(res) and
			m2=/^\s*Valuta\s+(\S+)/.match(res) and
			m3=/^\s*Datum\s+(\S+)/.match(res)
		ret[:accountnumber]=m1[2].gsub('.','')
		ret[:currency]=m2[1]
		ret[:sdate]=Date.strptime(m3[1],'%d-%m-%Y')

		# Nieuw saldo
		res=pipeio %W(pdftotext -nopgbrk -f 1 -l 1 -fixed 8 -r 150 -x 785 -y 566 -W #{1121-785} -H #{614-566} -layout - -)
		return false unless
			m1=/^(\s*)Debet(\s+)Credit\s*$/.match(res) and
			m2=/^\s*([0-9.]+),(\d{2})/.match(res)
		val=parsenum(m2[1],m2[2])
		# TODO: Check if this works, I don't have any statements with a negative balance
		val=-val if m2.to_s.length<(m1[1].length+"Debet".length+m1[2].length/2)
		ret[:balance_new]=val

		# Vorig saldo
		res=pipeio %W(pdftotext -nopgbrk -f 1 -l 1 -fixed 8 -r 150 -x 785 -y 1566 -W #{1121-785} -H #{1612-1566} -layout - -)
		return false unless
			m1=/^(\s*)Debet(\s+)Credit\s*$/.match(res) and
			m2=/^\s*([0-9.]+),(\d{2})/.match(res)
		val=parsenum(m2[1],m2[2])
		# TODO: Check if this works, I don't have any statements with a negative balance
		val=-val if m2.to_s.length<(m1[1].length+"Debet".length+m1[2].length/2)
		ret[:balance_old]=val

		# Transacties
		res=pipeio %W(pdftotext -nopgbrk -fixed 8 -r 150 -x 113 -y 686 -W #{1121-113} -H #{1547-686} -layout - -)
		res=res.lines.map { |l| l.chomp.ljust(113,' ') }
		return false if res.any? { |l| Format_check=~l }
		buf=[]
		res.each do |line|
			if /^\s*(\d+)\s*$/=~line[0...6] then
				return false unless parse_trans(buf,ret)
				buf=[]
			end
			buf << line
		end
		return false unless parse_trans(buf,ret)
		
		return ret
	end
end

def Symbols.read
	return if @read
	@symbols={}
	lines=IO.readlines(self)
	header=lines.shift.strip.split("\t")
	if header.pop!="Aliases" or header.first!="Name" then
		$stderr.puts "Unknown Symbols file format..."
		exit(1)
	end
	lines.each do |line|
		line=line.strip.split("\t").map { |v| v.length==0 ? nil : v }
		name=line.first
		values=Hash[header.zip(line)]
		if not values["ISIN"].nil? then
			values.merge! :maintype => "ISIN", :mainid => values["ISIN"]
		elsif not values["CUSIP"].nil? then
			values.merge! :maintype => "CUSIP", :mainid => values["CUSIP"]
		else
			values.merge! :maintype => "Unknown", :mainid => "Unknown"
		end
		aliases=line.drop(header.length)
		(aliases+[name]).each { |k| @symbols[k]=values }
	end
	@read=true
end

def Symbols.[](sym)
	read
	@symbols[sym]
end

def Symbols.include?(sym)
	read
	@symbols.include? sym
end

module OFX
	def self.convert(stmt)
		stocklist={}
		Erubis::Eruby.new(<<'END',:trim=>true,:escape=>true).result(OpenStruct.new(stmt).instance_eval { binding })
OFXHEADER:100
DATA:OFXSGML
VERSION:103
SECURITY:NONE
ENCODING:UNICODE
CHARSET:NONE
COMPRESSION:NONE
OLDFILEUID:NONE
NEWFILEUID:NONE

<OFX>
  <INVSTMTMSGSRSV1>
    <INVSTMTTRNRS>
      <TRNUID><%=accountnumber%>-<%=currency%>-<%=transactions.minmax_by{|v|v[:tnum]}.map{|v|v[:tnum]}*'-'%></TRNUID>
      <STATUS>
        <CODE>0</CODE>
        <SEVERITY>INFO</SEVERITY>
        <MESSAGE>SUCCESS</MESSAGE>
      </STATUS>
      <INVSTMTRS>
        <DTASOF><%=sdate.strftime('%Y%m%d')%></DTASOF>
        <CURDEF><%=currency%></CURDEF>
        <INVACCTFROM>
          <BROKERID><%=bank.upcase%></BROKERID>
          <ACCTID><%=accountnumber%>-<%=currency%></ACCTID>
        </INVACCTFROM>
        <INVTRANLIST>
          <DTSTART><%=transactions.min_by{|v|v[:tdate]}[:tdate].strftime('%Y%m%d')%></DTSTART>
          <DTEND><%=sdate.strftime('%Y%m%d')%></DTEND>
<%  transactions.each do |tran| -%>
<%    case tran[:type]   
        when :transfer, :interest, :fees
          unused_fields? tran, :type,:value,:tdate,:idate,:tnum,:name,:longdesc,:toacct,:fromacct,:currency,:netvalue,:xrate,:fees,:vat, " Ignored: ", :memo -%>
          <INVBANKTRAN>
            <STMTTRN>
              <TRNTYPE><%={:transfer=>(tran[:value]<0) ? 'DEBIT' : 'CREDIT',:interest=>'INT',:fees=>'FEE'}[tran[:type]]%></TRNTYPE>
              <DTPOSTED><%=tran[:tdate].strftime('%Y%m%d')%></DTPOSTED>
              <DTAVAIL><%=tran[:idate].strftime('%Y%m%d')%></DTAVAIL>
              <TRNAMT><%="%.02f"%tran[:value]%></TRNAMT>
              <FITID><%=tran[:tnum]%></FITID>
<%          if tran[:name] then -%>
              <NAME><%=tran[:name]%></NAME>
<%          end -%>
              <MEMO><%=tran[:longdesc]%></MEMO>
<%          if tran[:toacct] then -%>
              <BANKACCTTO>
                <BANKID></BANKID>
                <ACCTID><%=tran[:toacct]%></ACCTID>
                <ACCTTYPE>CHECKING</ACCTTYPE>
              </BANKACCTTO>
<%          end -%>
<%          if tran[:fromacct] then -%>
              <BANKACCTFROM>
                <BANKID></BANKID>
                <ACCTID><%=tran[:fromacct]%></ACCTID>
                <ACCTTYPE>CHECKING</ACCTTYPE>
              </BANKACCTFROM>
<%          end -%>
<%          if tran[:currency] then -%>
              <ORIGCURRENCY>
                <CURRATE><%="%.06f"%(1/tran[:xrate])%></CURRATE>
                <CURSYM><%=tran[:currency]%></CURSYM>
              </ORIGCURRENCY>
<%          end -%>
            </STMTTRN>
            <SUBACCTFUND>CASH</SUBACCTFUND>
          </INVBANKTRAN>
<%      when :buystock, :sellstock
          unused_fields? tran, :type,:value,:tdate,:idate,:tnum,:longdesc,:reinvestment,:amount,:price,:fees,:xrate,:currency, " Ignored: ", :netvalue,:exchange,:totalpos,:onum,:name
          stocklist[Symbols[tran[:name]][:mainid]]=Symbols[tran[:name]] if Symbols.include?(tran[:name]) -%>
<%        if tran[:type]==:buystock and not tran[:reinvestment] -%>
          <BUYSTOCK>
            <INVBUY>
<%        elsif tran[:type]==:buystock and tran[:reinvestment] -%>
          <REINVEST>
<%        elsif tran[:type]==:sellstock -%>
          <SELLSTOCK>
            <INVSELL>
<%        end -%>
              <INVTRAN>
                <FITID><%=tran[:tnum]%></FITID>
                <DTTRADE><%=tran[:tdate].strftime('%Y%m%d')%></DTTRADE>
                <MEMO><%=tran[:longdesc]%></MEMO>
              </INVTRAN>
              <SECID>
                <UNIQUEID><%=Symbols[tran[:name]][:mainid]%></UNIQUEID>
                <UNIQUEIDTYPE><%=Symbols[tran[:name]][:maintype]%></UNIQUEIDTYPE>
              </SECID>
              <UNITS><%=tran[:amount]*(tran[:type]==:sellstock ? -1 : 1)%></UNITS>
              <UNITPRICE><%="%.06f"%tran[:price]%></UNITPRICE>
<%          if tran[:fees] then -%>
              <FEES><%="%.02f"%tran[:fees]%></FEES>
<%          end -%>
              <TOTAL><%="%.02f"%tran[:value]%></TOTAL>
<%          if tran[:currency] then -%>
              <ORIGCURRENCY>
                <CURRATE><%="%.06f"%(1/tran[:xrate])%></CURRATE>
                <CURSYM><%=tran[:currency]%></CURSYM>
              </ORIGCURRENCY>
<%          end -%>
              <SUBACCTSEC>CASH</SUBACCTSEC>
<%        if tran[:type]==:buystock and not tran[:reinvestment] -%>
              <SUBACCTFUND>CASH</SUBACCTFUND>
            </INVBUY>
            <BUYTYPE>BUY</BUYTYPE>
          </BUYSTOCK>
<%        elsif tran[:type]==:buystock and tran[:reinvestment] -%>
            <INCOMETYPE>DIV</INCOMETYPE>
          </REINVEST>
<%        elsif tran[:type]==:sellstock -%>
              <SUBACCTFUND>CASH</SUBACCTFUND>
            </INVSELL>
            <SELLTYPE>SELL</SELLTYPE>
          </SELLSTOCK>
<%        end -%>
<%      when :distributedividend
          unused_fields? tran, :type,:value,:tdate,:idate,:tnum,:longdesc,:amount,:price,:sourcetax,:fees,:currency,:xrate, " Ignored: ", :netvalue,:exchange,:totalpos,:onum,:name
          stocklist[Symbols[tran[:name]][:mainid]]=Symbols[tran[:name]] if Symbols.include?(tran[:name]) -%>
          <INCOME>
            <INVTRAN>
              <FITID><%=tran[:tnum]%></FITID>
              <DTTRADE><%=tran[:tdate].strftime('%Y%m%d')%></DTTRADE>
              <MEMO><%=tran[:longdesc]%><%= tran[:fees] ? ', Provisie: %.02f'%tran[:fees] : '' %></MEMO>
            </INVTRAN>
            <SECID>
              <UNIQUEID><%=Symbols[tran[:name]][:mainid]%></UNIQUEID>
              <UNIQUEIDTYPE><%=Symbols[tran[:name]][:maintype]%></UNIQUEIDTYPE>
            </SECID>
            <INCOMETYPE>DIV</INCOMETYPE>
            <TOTAL><%="%.02f"%tran[:value]%></TOTAL>
<%        if tran[:currency] then -%>
            <ORIGCURRENCY>
              <CURRATE><%="%.06f"%(1/tran[:xrate])%></CURRATE>
              <CURSYM><%=tran[:currency]%></CURSYM>
            </ORIGCURRENCY>
<%        end -%>
            <SUBACCTSEC>CASH</SUBACCTSEC>
            <SUBACCTFUND>CASH</SUBACCTFUND>
<%        if tran[:sourcetax] then -%>
            <WITHHOLDING><%="%.02f"%tran[:sourcetax][1]%></WITHHOLDING>
<%        end -%>
          </INCOME>
<%      when :transferstock
          unused_fields? tran, :type,:tdate,:idate,:tnum,:name,:amount,:price,:longdesc,:toacct,:fromacct, " Ignored: ", :value,:netvalue,:exchange,:totalpos,:onum,:memo
          stocklist[Symbols[tran[:name]][:mainid]]=Symbols[tran[:name]] if Symbols.include?(tran[:name]) -%>
          <TRANSFER>
            <INVTRAN>
              <FITID><%=tran[:tnum]%></FITID>
              <DTTRADE><%=tran[:tdate].strftime('%Y%m%d')%></DTTRADE>
              <MEMO><%=tran[:longdesc]%></MEMO>
            </INVTRAN>
            <SECID>
              <UNIQUEID><%=Symbols[tran[:name]][:mainid]%></UNIQUEID>
              <UNIQUEIDTYPE><%=Symbols[tran[:name]][:maintype]%></UNIQUEIDTYPE>
            </SECID>
            <SUBACCTSEC>CASH</SUBACCTSEC>
            <UNITS><%=tran[:amount]%></UNITS>
<%          if tran[:toacct] then -%>
              <TFERACTION>OUT</TFERACTION>
<%          end -%>
<%          if tran[:fromacct] then -%>
              <TFERACTION>IN</TFERACTION>
<%          end -%>
            <POSTYPE>LONG</POSTYPE>
            <UNITPRICE><%="%.06f"%tran[:price]%></UNITPRICE>
<%          if tran[:toacct] then -%>
              <INVACCTTO>
                <BROKERID></BROKERID>
                <ACCTID><%=tran[:toacct]%></ACCTID>
              </INVACCTTO>
<%          end -%>
<%          if tran[:fromacct] then -%>
              <INVACCTFROM>
                <BROKERID></BROKERID>
                <ACCTID><%=tran[:fromacct]%></ACCTID>
              </INVACCTFROM>
<%          end -%>
          </TRANSFER>
<%    end -%>
<%  end -%>
        </INVTRANLIST>
        <INVBAL>
          <AVAILCASH><%="%.02f"%balance_new%></AVAILCASH>
          <MARGINBALANCE>0.00</MARGINBALANCE>
          <SHORTBALANCE>0.00</SHORTBALANCE>
        </INVBAL>
      </INVSTMTRS>
    </INVSTMTTRNRS>
  </INVSTMTMSGSRSV1>
  <SECLISTMSGSRSV1>
    <SECLIST>
<%  stocklist.each do |id,sym| -%>
      <STOCKINFO>
        <SECINFO>
          <SECID>
            <UNIQUEID><%=id%></UNIQUEID>
            <UNIQUEIDTYPE><%=sym[:maintype]%></UNIQUEIDTYPE>
          </SECID>
          <SECNAME><%=sym["Name"]%></SECNAME>
        </SECINFO>
      </STOCKINFO>
<%  end -%>
    </SECLIST>
  </SECLISTMSGSRSV1>
</OFX>
END
	end
end

statements=Dir.glob(Input).map do |f|
	Subject.replace f
	break unless v=AlexV1.parse
	v
end

exit if statements.nil?

all_symbols=true
statements.each do |s|
	s[:transactions].each do |t|
		if [:buystock, :sellstock, :distributedividend, :transferstock].include? t[:type] then
			unless Symbols.include? t[:name]
				$stderr.puts "Missing symbols for #{t[:name]}"
				all_symbols=false
			end
		end
	end
end

exit unless all_symbols

statements=statements.group_by { |v| [v[:accountnumber],v[:currency]].hash }.map do |k,stmtg|
	min,max=stmtg.minmax_by { |v| v[:sdate] }
	max[:old_balance]=min[:old_balance]
	max[:transactions]=stmtg.reduce([]) { |memo,v| memo+v[:transactions] }
	max
end

statements.each do |s|
	f="#{Output}/#{s[:accountnumber]}-#{s[:currency]}_#{s[:sdate].strftime('%Y%m%d')}.ofx"
	puts f
	IO.write f, OFX.convert(s)
end
