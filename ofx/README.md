# ofx2xml

A shell script that converts OFX SGML to XML to aid further processing.
Depends on OpenSP for SGML to XML conversion. Depends on LibOFX for the OFX 
DTD.

Example usage:

    ./ofx2xml /usr/share/libofx4/libofx/dtd/ofx160.dtd < input.ofx > output.xml

# ofxsaver

A shared library that hooks into the AqBanking Import function and outputs 
the raw OFX data to file descriptor 3. This OFX can then be used for further 
processing by other libraries. Note that multiple OFX files could be 
concatenated as a single output. Also depends on LibOFX to check the 
response status code. Why LibOFX and not just use AqBanking? Because the 
AqBanking parser is the worst.

Example usage:

    AQBANKING_LOGLEVEL=error AQOFXCONNECT_LOGLEVEL=error LD_PRELOAD=./ofxsaver.so aqbanking-cli request --transactions 3> output.ofx
