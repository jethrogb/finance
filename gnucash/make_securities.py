#!/usr/bin/env python
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

from sys import argv, exit
import re
import gnucash
from symbols import read_symbols
from util import wait_for_backup_file
from gnucash import \
     Session, GnuCashBackendException, gnucash_core, \
     ERR_BACKEND_LOCKED, ERR_FILEIO_FILE_NOT_FOUND, \
     GncCommodity, Account

def main():
	if len(argv) < 3:
		print 'Usage: python make_securities.py <gnucash-file> <symbols-file>'
		exit(1)
	
	gnucash_file=argv[1]
	
	secs=read_symbols(argv[2])
	
	sess=Session(gnucash_file)
	
	try:
		# Make sure all the commodities exist
		ct=sess.book.get_table()
		
		created_secs=0
		updated_secs=0
		total_secs=0
		for ns in ['CUSIP','ISIN']:
			total_secs+=len(secs[ns])
			for c in ct.get_commodities(ns):
				matched_sec=None
				for k in secs[ns]:
					sec=secs[ns][k]
					if sec['id']==c.get_cusip():
						matched_sec=sec
						break
				if matched_sec:
					matched_sec['c']=c
					updated=False
					if c.get_fullname()!=matched_sec['name']:
						c.set_fullname(matched_sec['name'])
						updated=True
					if c.get_mnemonic()!=matched_sec['symbol']:
						c.set_mnemonic(matched_sec['symbol'])
						updated=True
					if updated:
						updated_secs+=1
						print 'DEBUG: Updating Commodity', sec['name']
					del secs[ns][matched_sec['id']]
			for k in secs[ns]:
				sec=secs[ns][k]
				c=GncCommodity(sess.book,sec['name'],ns,sec['symbol'],sec['id'],10000)
				if c:
					ct.insert(c)
					created_secs+=1
					print 'DEBUG: Created Commodity', sec['name'], sec['id']
				else:
					print 'ERROR: Error creating Commodity', sec['name']

		print 'INFO:',total_secs,'commodities total,',created_secs,'created,',updated_secs,'updated.'

		wait_for_backup_file(gnucash_file)
		sess.save()
	except BaseException as e:
		print 'ERROR:',e
	finally:    
		sess.end()
		sess.destroy()

if __name__ == "__main__": main()
