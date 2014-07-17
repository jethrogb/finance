# alexparse.rb

Ruby script to parse Alex.nl PDF bank statements and convert them to OFX 
format. Depends on pdftotext. Requires a symbols file.

Example usage:

	./alexparse.rb 'Alex/*Rekening*Transactie*.pdf' Alex/ symbols.tsv

# Untested utilities

These utility scripts are no longer in use.

## util/sheet2csv.php

PHP script to convert Alex.nl Excel sheets to CSV.

## util/html2csv.php

PHP script to convert Alex.nl HTML tables to CSV.
