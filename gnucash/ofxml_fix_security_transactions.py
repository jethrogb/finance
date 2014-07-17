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

from xml.etree.cElementTree import ElementTree, dump
from sys import argv, exit
import re
import gnucash
from util import wait_for_backup_file, find_acct_by_number_and_currency, \
     _py_gnc_import_get_split_online_id, _py_xaccSplitListGetUniqueTransactions, \
     gnc_numeric_to_fraction, fraction_to_gnc_numeric, find_acct_by_path, conv_iban
from gnucash import \
     Session, GnuCashBackendException, gnucash_core, \
     ERR_BACKEND_LOCKED, ERR_FILEIO_FILE_NOT_FOUND, \
     GncCommodity, Account, Split
from fractions import Fraction
from accountmap import read_accountmap

def fix_buysell_transaction(tran,secsplit,cashsplit,xml,root,accountmap):
	print 'DEBUG: Fixing buy/sell', tran.GetDescription()
	fields={}
	for path in ('SECID/UNIQUEID', 'SECID/UNIQUEIDTYPE', 'UNITS', 'UNITPRICE', 'TOTAL', 'COMMISSION', 'TAXES', 'FEES', 'MARKUP', 'MARKDOWN', 'CURRENCY', 'ORIGCURRENCY', 'LOAD', 'REVERSALFEES', 'REVERSALFITID', 'GAIN', 'TAXEXEMPT', 'WITHHOLDING'):
		el=xml.find('./'+path)
		if not el is None and len(el.text.strip())>0:
			fields[path]=el.text.strip()
	
	error=False
	for field in ('MARKUP', 'MARKDOWN', 'CURRENCY', 'ORIGCURRENCY', 'LOAD', 'REVERSALFEES', 'REVERSALFITID', 'GAIN', 'TAXEXEMPT'):
		if field in fields:
			print 'ERROR: Transaction field', field, 'not implemented.'
			error=True
	for field in ('SECID/UNIQUEID', 'SECID/UNIQUEIDTYPE', 'UNITS', 'UNITPRICE', 'TOTAL'):
		if not field in fields:
			print 'ERROR: Required transaction field', field, 'missing.'
			error=True

	c=secsplit.GetAccount().GetCommodity()
	if c.get_namespace()!=fields['SECID/UNIQUEIDTYPE']:
		print "ERROR: Transaction's commodity namespace does not match. GNC:", c.get_namespace(), 'OFX:', fields['SECID/UNIQUEIDTYPE']
		error=True
	if c.get_cusip()!=fields['SECID/UNIQUEID']:
		print "ERROR: Transaction's unique ID does not match. GNC:", c.get_cusip(), 'OFX:', fields['SECID/UNIQUEID']
		error=True
	if gnc_numeric_to_fraction(secsplit.GetAmount())!=Fraction(fields['UNITS']):
		print "ERROR: Transaction number of units does not match. GNC:", float(gnc_numeric_to_fraction(secsplit.GetAmount())), 'OFX:', fields['UNITS']
		error=True
	if abs(gnc_numeric_to_fraction(cashsplit.GetAmount()))!=abs(Fraction(fields['TOTAL'])):
		print "ERROR: Transaction total amount does not match. GNC:", float(gnc_numeric_to_fraction(secsplit.GetAmount())), 'OFX:', fields['TOTAL']
		error=True
	
	if not error:
		tran.BeginEdit()
		try:
			secsplit.SetValue(fraction_to_gnc_numeric(Fraction(fields['UNITS'])*Fraction(fields['UNITPRICE'])))
			for field in ('COMMISSION', 'TAXES', 'FEES', 'WITHHOLDING'):
				if field in fields and Fraction(fields[field])!=0:
					split=Split(secsplit.GetBook())
					split.SetParent(tran)
					split.SetMemo(field.title())
					# Figure out destination account
					comm=c.get_namespace()+':'+c.get_cusip()
					found=False
					for lookup in (field+':'+comm,field,comm):
						if lookup in accountmap:
							dstacct=find_acct_by_path(root,accountmap[lookup])
							if not dstacct is None:
								split.SetAccount()
								found=True
								break
					if not found:
						print "ERROR: Couldn't find destination account for the",field.title(),'for',comm
						error=True
					split.SetValue(fraction_to_gnc_numeric(Fraction(fields[field])))
			if not tran.IsBalanced():
				print "ERROR: Transaction is not balanced."
				error=True
		except:
			tran.RollbackEdit()
			raise
		if error:
			tran.RollbackEdit()
		else:
			tran.CommitEdit()
	
	return not error

def fix_income_transaction(tran,incsplit,cashsplit,xml,root,accountmap):
	print 'DEBUG: Fixing income', tran.GetDescription()
	fields={}
	for path in ('SECID/UNIQUEID', 'SECID/UNIQUEIDTYPE', 'INCOMETYPE', 'TAXEXEMPT', 'WITHHOLDING'):
		el=xml.find('./'+path)
		if not el is None and len(el.text.strip())>0:
			fields[path]=el.text.strip()
	
	error=False
	for field in ('TAXEXEMPT'):
		if field in fields:
			print 'ERROR: Transaction field', field, 'not implemented.'
			error=True
	for field in ('SECID/UNIQUEID', 'SECID/UNIQUEIDTYPE', 'INCOMETYPE'):
		if not field in fields:
			print 'ERROR: Required transaction field', field, 'missing.'
			error=True

	secacct=cashsplit.GetAccount().lookup_by_code(fields['SECID/UNIQUEID'])
	if secacct is None or secacct.get_instance() is None:
		print "ERROR: Can't find subaccount with code:", fields['SECID/UNIQUEID']
		error=True
	else:
		c=secacct.GetCommodity()
		if c.get_namespace()!=fields['SECID/UNIQUEIDTYPE']:
			print "ERROR: Transaction's commodity namespace does not match. GNC:", c.get_namespace(), 'OFX:', fields['SECID/UNIQUEIDTYPE']
			error=True
		if c.get_cusip()!=fields['SECID/UNIQUEID']:
			print "ERROR: Transaction's unique ID does not match. GNC:", c.get_cusip(), 'OFX:', fields['SECID/UNIQUEID']
			error=True

	if not error:
		tran.BeginEdit()
		try:
			split=Split(incsplit.GetBook())
			split.SetParent(tran)
			actions={"CGLONG":"LTCG", "CGSHORT":"STCG", "DIV":"Dividend", "INTEREST":"Interest", "MISC":"Income"}
			split.SetAction(actions[fields['INCOMETYPE']])
			split.SetAccount(secacct)
			split.SetAmount(fraction_to_gnc_numeric(Fraction(0)))
			for field in ('WITHHOLDING',):
				if field in fields and Fraction(fields[field])!=0:
					split=Split(incsplit.GetBook())
					split.SetParent(tran)
					split.SetMemo(field.title())
					# Figure out destination account
					comm=c.get_namespace()+':'+c.get_cusip()
					found=False
					for lookup in (field+':'+comm,field,comm):
						if lookup in accountmap:
							dstacct=find_acct_by_path(root,accountmap[lookup])
							if not dstacct is None:
								split.SetAccount(dstacct)
								found=True
								break
					if not found:
						print "ERROR: Couldn't find destination account for the",field.title(),'for',comm
						error=True
					amt=Fraction(fields[field])
					split.SetValue(fraction_to_gnc_numeric(amt))
					orig=gnc_numeric_to_fraction(incsplit.GetValue())
					incsplit.SetValue(fraction_to_gnc_numeric(orig-amt))
			if not tran.IsBalanced():
				print "ERROR: Transaction is not balanced."
				error=True
		except:
			tran.RollbackEdit()
			raise
		if error:
			tran.RollbackEdit()
		else:
			tran.CommitEdit()
	
	return not error

def main():
	if len(argv) < 4:
		print 'Usage: python ofxml_make_commodity_accounts.py <gnucash-file> <ofxml-file> <accountmap-file>'
		exit(1)
		
	gnucash_file=argv[1]
	
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

	fitids={}
	for itran in doc.findall('.//INVBUY')+doc.findall('.//INVSELL')+doc.findall('.//REINVEST'):
		fitid=itran.find('./INVTRAN/FITID')
		if not fitid is None:
			fitid=fitid.text.strip()
		if fitid in fitids:
			print "ERROR: Non-unique FITID found:", fitid
			exit(1)
		fitids[fitid]=itran
		
	# Fantastic, the FITID is not saved by GnuCash for income transactions...
	# Index by (date,amount,memo) instead
	incometrns={}
	for itran in doc.findall('.//INCOME'):
		fields={}
		for path in ('INVTRAN/DTTRADE', 'INVTRAN/MEMO', 'TOTAL'):
			el=itran.find('./'+path)
			if not el is None and len(el.text.strip())>0:
				fields[path]=el.text.strip()
		if len(fields)!=3:
			print "ERROR: Can't create identifier for INCOME transaction, ignoring."
		incometrns[(fields['INVTRAN/DTTRADE'][0:8],fields['INVTRAN/MEMO'],Fraction(fields['TOTAL']))]=itran

	sess=Session(gnucash_file)
	
	try:
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
		
		accountmap=read_accountmap(argv[3],acct.GetCode()+'-'+acct.GetCommodity().get_mnemonic())

		# Find child Stock/Mutual accounts
		secaccts=[] # SwigPyObject is not Hashable :(
		for cacct in acct.get_descendants():
			atype=cacct.GetType()
			if atype==gnucash_core.ACCT_TYPE_STOCK or atype==gnucash_core.ACCT_TYPE_MUTUAL:
				secaccts.append(cacct.get_instance())
				
		# Find income accounts
		incaccts=[] # SwigPyObject is not Hashable :(
		for typ in accountmap:
			if typ[0:6]=="INCOME":
				inst=find_acct_by_path(root,accountmap[typ]).get_instance()
				if not (inst is None or inst in incaccts):
					incaccts.append(inst)

		if len(incaccts)==0 and len(incometrns)>0:
			print 'WARNING: no income accounts defined for account',acct.GetCode()+'-'+acct.GetCommodity().get_mnemonic()
			print 'WARNING: income transactions will not be fixed'

		# Go through all transactions
		for tran in _py_xaccSplitListGetUniqueTransactions(acct.GetSplitList()):
			# Consider fixing if transaction ...
			# ... has exactly 2 splits
			# ... has 1 split with a child Stock/Mutual account
			# ... has 1 split with an online ID
			splits=tran.GetSplitList()
			if len(splits)==2:
				cashsplit=None
				secsplit=None
				incsplit=None
				online_id=None
				for split in splits:
					if split.GetAccount().get_instance() in secaccts:
						secsplit=split
					if split.GetAccount().get_instance() in incaccts:
						incsplit=split
					if split.GetAccount().get_instance()==acct.get_instance():
						cashsplit=split
					oid=_py_gnc_import_get_split_online_id(sess,split)
					if not oid is None:
						if online_id is None:
							online_id=oid
						else:
							online_id=False
				if not (cashsplit is None or secsplit is None or online_id is None or online_id is False):
					if not online_id in fitids:
						# This can happen if we encounter a transaction outside of this OFX period
						#print 'DEBUG: FITID',online_id,'not found in OFX file.'
						continue
					fix_buysell_transaction(tran,secsplit,cashsplit,fitids[online_id],root,accountmap)
				elif not (cashsplit is None or incsplit is None):
					date=tran.RetDatePostedTS().strftime('%Y%m%d')
					memo=re.sub(' +',' ',tran.GetDescription()) # GnuCash importer likes to insert spaces randomly
					amt=gnc_numeric_to_fraction(cashsplit.GetAmount())
					if not (date,memo,amt) in incometrns:
						# This can happen if we encounter a transaction outside of this OFX period
						#print "DEBUG: No match for income transaction",date,memo,amt
						continue
					fix_income_transaction(tran,incsplit,cashsplit,incometrns[(date,memo,amt)],root,accountmap)

		wait_for_backup_file(gnucash_file)
		sess.save()
	except BaseException as e:
		print 'ERROR:',e
	finally:    
		sess.end()
		sess.destroy()

if __name__ == "__main__": main()
