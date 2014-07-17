# GnuCash investment import tools

This directory contains various tools to aid the importing of investment 
transcations from OFX files into GnuCash. These files make a lot of 
assumptions about the way my books are setup, so your mileage may vary. Here 
is a non-exhaustive list of assumptions:

  * All relevant securities are in the namespaces 'CUSIP' and 'ISIN'.
  * The identifier for securities throughout the tools is its CUSIP/ISIN, not
    the ticker symbol.
  * All relevant stock/fund accounts are directly under the appropriate
    brokerage account.
  * The 'code' of all relevant stock/fund accounts is its commodity's
    CUSIP/ISIN.
  * Your GnuCash file uses the XML format.

Some GnuCash quirks that we have to work around:

  * The FITID of income transactions is not saved during import.
  * xaccSplitListGetUniqueTransactions doesn't work in python.
  * gnc_import_get_split_online_id doesn't work in python.
  * You can't save a GnuCash file twice in the same second, as the backup file
    will already exist and the save will fail.

Also note that the AqBanking OFX parser is pretty bad, and the resulting 
GnuCash import is also bad. Therefore, I only use AqBanking to retrieve the OFX
but do all the processing in Python or with the regular GnuCash OFX importer.

# make_securities.py

A Python script that creates GnuCash commodities from a tab-separted symbols 
file.

Example usage:

    ./make_securities.py gnucash-file symbols.tsv

# ofxml_make_commodity_accounts.py

A Python script that creates stock accounts under the main account for the 
securities in an OFX XML file. Use the `ofx2xml` script in the `ofx/` 
directory to convert OFX files to XML.

Example usage:

    ./ofxml_make_commodity_accounts.py gnucash-file input.xml symbols.tsv

# ofxml_fix_security_transactions.py

A Python script that given an OFX XML file fixes securities transactions
imported from the correspoding OFX by the limited GnuCash importer. The current
fixes are:
  
  * Add commission/fees/taxes to stock buys/sells/income
  * Add a split of amount 0 to the stock account for income transactions

Example usage:

    ./ofxml_make_commodity_accounts.py gnucash-file input.xml accountmap.tsv
