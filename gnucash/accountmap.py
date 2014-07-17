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

# retuns a dict {type:path}
# Where:
#   type is either COMMISSION, FEES, TAXES or one of those followed by :Namespace:Id or just Namespace:Id
#   path is an array of the account path
def read_accountmap(filename,account):
	ret={}
	f=open(filename,'r')
	if f:
		headers=f.readline().strip().split('\t')
		headers.pop()
		for l in f:
			v=l.rstrip().split('\t')
			kv=dict(zip(headers,v))
			if kv['Acct-Cur']==account:
				ret[kv['Type']]=v[len(headers):]
		f.close()
	return ret
