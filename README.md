# Jethro's finance tools

This is a collection of tools that I use to do my accounting. They are not 
meant to be of use to anyone else in particular. The tools are meant for use 
on a GNU/Linuxy system. The tools are written in whatever language I felt 
like at the time of development. The following is a non-exhaustive list of 
dependencies:

  * Ruby
  * Python
  * Bash
  * GnuCash (with Python bindings)
  * libofx
  * libaqbanking (with CLI tools)
  * OpenSP
  * csplit
  * pdftotext

# run_all.bash

This file runs all the tools to do a single online import. It does the 
following things in that order:

  * Transform Alex.nl PDF statements into OFX
  * Use aqbanking-cli to request all transactions from all banks, and save the
    returned OFX data.
  * Go through all OFX data and create missing securities and stock accounts.
  * Launch GnuCash and ask the user to import all the OFX files and close
    GnuCash.
  * Go through the OFX data and imported transactions, and modify them where
    appropriate.

# Symbols file

Several utilities make use of a symbols database to match share/fund/ETF 
names. This file is in tab-separated values format, where the first column 
must be named `Name` and the last column `Aliases`. Records can have more 
fields than there are header columns, the excess fields will be considered 
other aliases. Other columns you should include are `ISIN` and `CUSIP`.

# Accountmap file

Several utilities make use of an account map database to match securities 
income/expense transactions to their appropriate accounts. This file is in 
tab-separated values format, where the last column must be named `Path`. You 
must also include the `Acct-Cur` and `Type` columns. `Acct-Cur` identifies 
the parent brokerage account by account_code-currency_mnemonic, e.g. 
12345678 -USD. `Type` can be one of COMMISSION, FEES, TAXES, WITHHOLDING, 
INCOME, or one of those followed by :Namespace:Id, or just Namespace:Id, 
where Id is the CUSIP/ISIN. The `Path` field is a tab-separated field of 
account names specifying the full account path of the target account.
