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

# retuns a dict {CUSIP:dict,ISIN:dict}
# These dicts have keys id: with values of dict {name:,symbol:,id:}
# Where:
#   id is the CUSIP or ISIN, as appropriate
#   symbol is the ticker symbol
#   name is the name
def read_symbols(filename):
	secs={'CUSIP': {}, 'ISIN': {}}
	f=open(filename,'r')
	if f:
		headers=f.readline().strip().split('\t')
		headers.pop()
		for l in f:
			v=l.rstrip().split('\t')
			v+=[""]*(len(headers)-len(v))
			v=dict(zip(headers,v))
			if len(v['ISIN'])>0:
				secs['ISIN'][v['ISIN']]={'name': v['Name'], 'symbol': v['Symbol'], 'id': v['ISIN']}
			if len(v['CUSIP'])>0:
				secs['CUSIP'][v['CUSIP']]={'name': v['Name'], 'symbol': v['Symbol'], 'id': v['CUSIP']}
		f.close()
	return secs
