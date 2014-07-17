#!/usr/bin/env bash
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

TMP_DIR="$(pwd)/tmp"
OFX_DIR="/PATH/TO/OFX/OUTPUT/DIR"

ALEX_INPUT='/PATH/TO/ALEX/STATEMENTS/*.pdf'
ALEX_OUTPUT="$TMP_DIR"
GNUCASH='/PATH/TO/GNUCASH/BOOKS.gnucash'
SYMBOLS='/PATH/TO/symbols'
ACCOUNTMAP='/PATH/TO/accountmap'

set -o pipefail

notcontains() {
	perl -pe 'END { exit $status } $status=1 if /'$1'/;'
}

stateQ() {
	if [ -f "$TMP_DIR/_state_$1" ]; then
		echo "Skipping $2."
		return 1
	else
		echo "Processing $2"
		return 0
	fi
}

state() {
	touch "$TMP_DIR/_state_$1"
}

if stateQ alex "Alex statements"; then
	pushd alex &> /dev/null
	if ./alexparse.rb "$ALEX_INPUT" "$ALEX_OUTPUT" "$SYMBOLS" 2>&1 >/dev/null | grep --color=never .; then
		echo "Error, aborting."
		exit
	fi
	popd &> /dev/null
	state alex
fi

if  stateQ aqbank "obtaining online transactions"; then
	if ! AQBANKING_LOGLEVEL=error AQOFXCONNECT_LOGLEVEL=error LD_PRELOAD=ofx/ofxsaver.so aqbanking-cli request --transactions 3>&1 1>/dev/null | csplit -z -s -b '%02d.ofx' -f "$TMP_DIR/ofxconnect" - '/^OFXHEADER:/' '{*}'; then
		echo "Error, aborting."
		exit
	fi
	state aqbank
fi

if stateQ xml "OFX to XML"; then
	for i in "$TMP_DIR/"*.ofx; do
		xml="$(dirname $i)/$(basename $i .ofx).xml"
		ofx/ofx2xml /usr/share/libofx4/libofx/dtd/ofx160.dtd < "$i" > "$xml"
	done
	state xml
fi

if stateQ securities "GnuCash securities"; then
	pushd gnucash &> /dev/null

	echo "Creating securities"
	if ! ./make_securities.py "$GNUCASH" "$SYMBOLS" 2> /dev/null | egrep -v '^DEBUG:' | notcontains '^ERROR:'; then
		echo "Error, aborting."
		exit
	fi

	echo "Creating commodity accounts"
	for i in "$TMP_DIR/"*.xml; do
		if grep -q INVSTMTMSGSRSV1 "$i"; then
			if ! ./ofxml_make_commodity_accounts.py "$GNUCASH" "$i" "$SYMBOLS" 2> /dev/null | egrep -v '^DEBUG:' | notcontains '^ERROR:'; then
				echo "Error, aborting."
				exit
			fi
		fi
	done

	popd &> /dev/null
	state securities
fi

if stateQ copyofx "Copy OFX to output directory"; then
	date=$(date +%Y%m%d%H%M%S)
	for i in "$TMP_DIR/"*.ofx; do
		cp "$i" "$OFX_DIR/"$date"_$(basename $i)"
	done
	echo "Output files left in $OFX_DIR/"$date"_*.ofx"
	state copyofx
fi

if stateQ gnucash "Import using GnuCash"; then
	echo "Launching GnuCash"
	gnucash "$GNUCASH" &> /dev/null & disown

	echo
	echo "Import the following files now:"
	echo "$OFX_DIR/"
	pushd "$OFX_DIR/" &> /dev/null
	ls -1 "$date"_*.ofx|sed 's/^/	/'
	popd &> /dev/null
	echo -n "When done importing, *close GnuCash*, and "
	while true; do
		echo -n "type (C)ontinue or (Q)uit: "
		read response
		case "$response" in
			[cC]*)
				break
				;;
			[qQ]*)
				exit
				;;
		esac
	done
	state gnucash
fi

if stateQ fixsectrans "Fixing GnuCash securities transactions"; then
	pushd gnucash &> /dev/null
	for i in "$TMP_DIR/"*.xml; do
		if grep -q INVSTMTMSGSRSV1 "$i"; then
			if ! ./ofxml_fix_security_transactions.py "$GNUCASH" "$i" "$ACCOUNTMAP" 2> /dev/null | egrep -v '^DEBUG:' | notcontains '^ERROR:'; then
				echo "Error, aborting."
				exit
			fi
		fi
	done
	popd &> /dev/null
	state fixsectrans
fi

echo "Done."

rm -rf "$TMP_DIR/"*
