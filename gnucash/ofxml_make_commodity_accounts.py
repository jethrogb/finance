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

from xml.etree.cElementTree import ElementTree
from sys import argv, exit
import re
import gnucash
from symbols import read_symbols
from util import wait_for_backup_file, find_acct_by_number_and_currency, conv_iban
from gnucash import \
     Session, GnuCashBackendException, gnucash_core, \
     ERR_BACKEND_LOCKED, ERR_FILEIO_FILE_NOT_FOUND, \
     GncCommodity, Account

def main():
	if len(argv) < 3:
		print 'Usage: python ofxml_make_commodity_accounts.py <gnucash-file> <ofxml-file> [symbols-file]'
		exit(1)
		
	gnucash_file=argv[1]
	
	symbols_file=False
	if len(argv)>=4:
		symbols_file=read_symbols(argv[3])
	
	doc=ElementTree(file=argv[2])
	
	acctids=doc.findall('./INVSTMTMSGSRSV1/INVSTMTTRNRS/INVSTMTRS/INVACCTFROM/ACCTID')
	if len(acctids)!=1:
		print 'ERROR: No unique account number found in OFX: found', len(acctids)
		return
	acctid=acctids[0].text.strip()
	acctcur='any'
	m=re.search('^(.*)-([A-Z]{3})$',acctid)
	if m:
		acctid=m.group(1)
		acctcur=m.group(2)
	print "INFO: Account number:", acctid, "Currency:", acctcur

	missing_symbols=False
	secs=[]
	for sec in doc.findall('./SECLISTMSGSRSV1/SECLIST/*/SECINFO'):
		id=sec.findall('./SECID/UNIQUEID')[0].text.strip()
		type=sec.findall('./SECID/UNIQUEIDTYPE')[0].text.strip()
		name=sec.findall('./SECNAME')[0].text.strip()
		symbol=sec.findall('./TICKER')
		if len(symbol):
			symbol=symbol[0].text.strip()
		else:
			symbol=None
		if symbols_file:
			if id in symbols_file[type]:
				name=symbols_file[type][id]['name']
				symbol=symbols_file[type][id]['symbol']
			else:
				print "WARNING: Missing symbol for", type, id, name, symbol
				missing_symbols=True
		secs.append({'id': id, 'type': type, 'name': name, 'symbol': symbol})

	print "DEBUG: Found", len(secs), "commodities."

	sess=Session(gnucash_file)
	
	try:
		# Make sure all the commodities exist
		ct=sess.book.get_table()
		
		for ns in ['CUSIP','ISIN']:
			for c in ct.get_commodities(ns):
				matched_sec=None
				for sec in secs:
					if sec['type']==ns and sec['id']==c.get_cusip():
						sec['c']=c
						break

		missing_secs=False
		for i,sec in enumerate(secs):
			if not 'c' in sec:
				print 'WARNING: Missing commodity', sec['type'],sec['id'],sec['name'],sec['symbol']
				missing_secs=True
				
		if missing_secs or missing_symbols:
			print 'ERROR: Missing symbols or commodities, aborting.'
			return
		
		# Find GNC parent account
		root=sess.book.get_root_account()
		matched_accts=find_acct_by_number_and_currency(root,acctid,acctcur)
		if len(matched_accts)==0:
			from_iban=conv_iban(acctid)
			if from_iban:
				matched_accts=find_acct_by_number_and_currency(root,from_iban,acctcur)
			
		if len(matched_accts)!=1:
			print 'ERROR: No unique account this number/currency; found', len(matched_accts)
			return
		
		acct=matched_accts[0]
		print 'DEBUG: Found parent account:',acct.GetName()
		
		# Make sure the account has the appropriate stock accounts
		created_accounts=0
		for sec in secs:
			matched_acct=None
			for secacct in acct.get_children():
				if secacct.GetCommodity().get_instance()==sec['c'].get_instance():
					matched_acct=secacct
					break
			if not matched_acct:
				secacct=Account(sess.book)
				if secacct:
					secacct.SetName(sec['name'])
					secacct.SetType(gnucash.ACCT_TYPE_STOCK)
					secacct.SetCommodity(sec['c'])
					secacct.SetCode(sec['id'])
					acct.append_child(secacct)
					created_accounts+=1
					print 'DEBUG: Created Account',sec['name']
				else:
					print 'ERROR: Error creating Account',sec['name']
					
		print 'INFO:',len(secs),'accounts total',created_accounts,'created.'
		
		wait_for_backup_file(gnucash_file)
		sess.save()
	except BaseException as e:
		print 'ERROR:',e
	finally:    
		sess.end()
		sess.destroy()

if __name__ == "__main__": main()
