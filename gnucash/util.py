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

from os.path import isfile
from time import strftime, sleep
from datetime import datetime
from xml.etree.cElementTree import ElementTree
import gzip
import gnucash
from gnucash import GncNumeric
from fractions import Fraction

def wait_for_backup_file(filename):
	if isfile(filename+'.'+strftime('%Y%m%d%H%M%S')+'.gnucash'):
		sleep(1.010-(datetime.now().microsecond/1000000.0))

def is_ascii(s):
    return all(ord(c) < 128 for c in s)

def conv_iban(s):
	# Alphanumeric string, first two chars are letters, second two are digits?
	if is_ascii(s) and s[0:2].isalpha() and s[2:4].isdigit() and s.isalnum():
		# This could be an IBAN, verify check digits
		tr=dict(list((str(i),str(i)) for i in xrange(0,10))+list((chr(i+65),str(i+10)) for i in xrange(0,26)))
		if int(''.join(tr[ch] for ch in s[4:]+s[0:4]))%97==1L:
			# Check digit matches!
			if s[0:2]=='NL':
				return str(int(s[8:]))
			else:
				print "ERROR: Don't know how to convert IBAN in to account number:", s
	return False

def find_acct_by_number_and_currency(root,acctid,acctcur='any'):
	matched_accts=[]
	for acct in root.get_descendants():
		c=acct.GetCommodity()
		if acctid==acct.GetCode() and (acctcur=='any' or (c.is_currency() and c.get_mnemonic()==acctcur)):
			matched_accts.append(acct)
	return matched_accts

def find_acct_by_path(root,path_array):
	ret=root.lookup_by_full_name(gnucash.gnucash_core_c.gnc_get_account_separator_string().join(path_array))
	if ret is not None and ret.get_instance() is None:
		return None
	return ret

def gnc_numeric_to_fraction(numeric):
	return Fraction(numeric.num(), numeric.denom())

def fraction_to_gnc_numeric(fraction):
	return GncNumeric(fraction.numerator,fraction.denominator)

# This emulates gnc_import_get_split_online_id by reading the GnuCash XML file
# until such a time as that function is exported to python
def _py_gnc_import_get_split_online_id(session,split):
	if not hasattr(_py_gnc_import_get_split_online_id, "cache"):
		_py_gnc_import_get_split_online_id.cache={}
	if not session in _py_gnc_import_get_split_online_id.cache:
		cache={}
		f=open(session.get_file_path(),'rb')
		if f:
			if (f.read(2) == '\x1f\x8b'):
				f.seek(0)
				f=gzip.GzipFile(fileobj=f)
			else:
				f.seek(0)
			xml=ElementTree(file=f)
			f.close()
			ns={"slot":"http://www.gnucash.org/XML/slot",
				"split":"http://www.gnucash.org/XML/split",
				"trn":"http://www.gnucash.org/XML/trn"}
			for el_split in xml.iterfind('.//trn:split',ns):
				for el_slot in el_split.iterfind('split:slots/slot',ns):
					el_key=el_slot.find('slot:key',ns)
					if not el_key is None and el_key.text=="online_id":
						el_guid=el_split.find("split:id[@type='guid']",ns)
						el_val=el_slot.find('slot:value',ns)
						if not el_guid is None and not el_val is None:
							cache[el_guid.text]=el_val.text
		_py_gnc_import_get_split_online_id.cache[session]=cache
	if session in _py_gnc_import_get_split_online_id.cache:
		cache=_py_gnc_import_get_split_online_id.cache[session]
		guid=split.GetGUID().to_string()
		if guid in cache:
			return cache[guid]
	return None

# This emulates xaccSplitListGetUniqueTransactions
# until such a time as GList support is added to python
def _py_xaccSplitListGetUniqueTransactions(splits):
	ret=[]
	seen=[] # SwigPyObject is not Hashable :(
	for split in splits:
		tran=split.GetParent()
		if not tran.get_instance() in seen:
			seen.append(tran.get_instance())
			ret.append(tran)
	return ret
