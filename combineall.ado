*! combineall - Stata module to combine (append, merge, or joinby) or convert all files (.dta, ASCII, or Excel) in a directory
*! v2.0.2 09nov2026 Eric A. Booth, Sr Researcher, Texas 2036 <eric.a.booth@gmail.com>
*!                  Elizabeth Teas, Sr Research Scientist, Far Harbor, LLC <elizabeth@farharbor.com>
*! first released 2011 (v1.0.0, April 2011, Eric A. Booth)
*! v2.0.0 modernizes the 2011 engine (version 16 floor; import delimited and
*! import excel replace insheet) and grafts a harmonization layer, active
*! under cmethod(append): map(), year(), strict, char varname[source]
*! provenance, and a variable-by-year harmonization table.
*! v2.0.2 reads delimited files with bindquote(strict), so a quoted field
*! that contains a line break stays one cell instead of splitting the row.
*! A stray-quote rule guards it: when a cell has a line break and a later
*! line of that cell looks like a data row (at least k-1 delimiters for k
*! columns; for k <= 2 also an id-like leading token), an unmatched quote
*! such as an inch mark joined rows, so combineall warns and uses loose
*! binding.  Otherwise strict is kept silently.  strictquotes skips the rule.

cap program drop combineall
program define combineall, rclass
version 16
syntax [using/] , [CMETHod(str asis) Directory(str asis) REPLace ///
	FILEtype(str asis) FILEID(str asis)  ///
	MType(str asis) MVARs(str asis) _Merge  ///
	DELIMiter(str asis) PREfix(str asis) SUFfix(str asis)   ///
	TOSTRing  KEEPconverted XMLopts(str asis) ///
	MAP(str asis) Year(string) STRICT STRICTQuotes * ]
						**add ability to navigate subdirs later**
*----------error checking (2011 engine)----------*
	**working directory**
		*-- default use the pwd if no dir is specified
		*-- (v2: resolved before the using default so the default output
		*--  lands in the working directory, not the filesystem root)
	if `"`directory'"' == ""  loc directory "`c(pwd)'"
	if `"`directory'"' != "" loc directory: subinstr local directory `"""' "", all
	**Target/Output File (using)**
	if `"`using'"' == "" {
		loc using "`directory'/combineall_output.dta"
		}
	**v2: strip only a trailing .dta extension (the 2011 engine stripped
	**every period, which mangled dotted directory names)**
	if lower(substr(`"`using'"', -4, 4)) == ".dta" {
		loc using = substr(`"`using'"', 1, strlen(`"`using'"') - 4)
		}
	loc using: subinstr local using `"""' "", all
	cap confirm file `"`using'.dta"'
		if !_rc & `"`replace'"' == "" {
			noi di as err `"File `using'.dta already exists! Specify {bf:replace} option to overwrite"'
			exit 198
			}
	**create `using2' to remove it from list to be converted/appended/etc
		loc using2 `"`using'"'
		loc _slash = max(strrpos(`"`using2'"', "/"), strrpos(`"`using2'"', "\"))
		if `_slash' > 0 loc using2 = substr(`"`using2'"', `_slash' + 1, .)
	**check cmethod**
	if `"`cmethod'"' == "" noi di as txt `"cmethod(convertonly) assumed"'
	if `"`cmethod'"' == "" loc cmethod "convertonly"
	if `"`cmethod'"' != "" loc cmethod: subinstr local cmethod `"""' "", all
	if `"`cmethod'"' != ""  loc cmethod = lower(`"`cmethod'"')
		if !inlist(`"`cmethod'"', "merge", "append", "joinby", "convertonly") {
			noi di as err `"cmethod() must be merge, append, joinby, or convertonly"'
			exit 198
			}
	**mtype(default 1:1)**
	if `"`mtype'"' == "" loc mtype "1:1"
		if `"`mtype'"' != "" loc mtype: subinstr local mtype `"""' "", all
	if !inlist(`"`mtype'"', "1:1", "m:m", "1:m", "m:1") {
		noi di as err `"mtype() must be either 1:1, m:m, 1:m, or m:1 (see {help merge} for more on merge types)"'
		exit 198
		}
		**(v2: these two checks tested mtype in v1.0.0, so they never fired)**
		if `"`cmethod'"' == "merge" & `"`mvars'"' == "" {
			di as err `"Specify mvars() for cmethod(merge)"'
			exit 198
			}
		if `"`cmethod'"' == "joinby" & `"`mvars'"' == "" {
			di as err `"Specify mvars() for cmethod(joinby)"'
			exit 198
			}
	**mvar and fileid**
		if `"`mvars'"' != "" loc mvars: subinstr local mvars `"""' "", all
		if `"`fileid'"' != "" loc fileid: subinstr local fileid `"""' "", all
	**filetype (default csv)**
	if `"`filetype'"' == "" loc filetype "csv"
	if `"`filetype'"' != "" {
		loc filetype:subinstr local filetype "."  "", all
		loc filetype: subinstr local filetype `"""'  "", all
		}
	**delimiter (v2: translated to import delimited syntax)**
	if `"`delimiter'"' == "" loc delimiter ","
	loc delimiter:subinstr local delimiter `"""' "", all
	if index(`"`delimiter'"', "tab")        loc dddd `" delimiters("\t") "'
	else if index(`"`delimiter'"', "comma") loc dddd `" delimiters(",") "'
	else                                    loc dddd `" delimiters("`delimiter'") "'
	**prefix/suffix**
	foreach ps in prefix suffix {
	if `"``ps''"' != "" {
		loc `ps':subinstr local `ps' "." "", all count( local _pscount)
		if `_pscount' > 0 di as txt `"Period character removed from `ps'() option"'
		loc `ps':subinstr local `ps' `"""' "", all
			}
		}
	**convertonly implies keepconverted (v2: the 2011 engine deleted the
	**converted files unless keepconverted was also specified)**
	if `"`cmethod'"' == "convertonly" loc keepconverted "keepconverted"

*----------harmonization layer checks (v2.0.0)----------*
	if (`"`map'"' != "" | `"`year'"' != "" | "`strict'" != "") & `"`cmethod'"' != "append" {
		di as err "map(), year(), and strict require cmethod(append)"
		exit 198
		}
	if (`"`year'"' != "" | "`strict'" != "") & `"`map'"' == "" {
		di as err "year() and strict require map()"
		exit 198
		}
	if `"`map'"' != "" loc map: subinstr local map `"""' "", all

*----------combine files----------*
preserve
	clear
	**read and validate the map CSV (harmonization layer)**
	loc nmap 0
	if `"`map'"' != "" {
		confirm file `"`map'"'
		_cmb_qguard `"`map'"', varnames(1) case(lower) ///
			stringcols(_all) `strictquotes'
		foreach c in oldname newname firstyear lastyear {
			cap confirm variable `c', exact
			if _rc {
				di as err "map file `map' must have columns " ///
					"oldname,newname,firstyear,lastyear (missing: `c')"
				exit 198
				}
			}
		loc nmap = _N
		forval i = 1/`nmap' {
			loc old`i' = strtrim(oldname[`i'])
			loc new`i' = strtrim(newname[`i'])
			loc fys    = strtrim(firstyear[`i'])
			loc lys    = strtrim(lastyear[`i'])
			loc skip`i' 0
			if "`old`i''" == "" & "`new`i''" == "" {
				loc skip`i' 1                     // blank row: ignore
				continue
				}
			cap confirm names `old`i''
			if !_rc cap confirm names `new`i''
			if _rc {
				di as err "map row `i': oldname/newname must be valid " ///
					"Stata variable names (got: `old`i'' -> `new`i'')"
				exit 198
				}
			foreach w in fys lys {
				if "``w''" != "" {
					cap confirm integer number ``w''
					if _rc {
						di as err "map row `i': firstyear/lastyear must be " ///
							"integer years or blank (got: ``w'')"
						exit 198
						}
					}
				}
			loc fy`i' = cond("`fys'" == "", 0,    real("`fys'"))
			loc ly`i' = cond("`lys'" == "", 9999, real("`lys'"))
			if `fy`i'' > `ly`i'' {
				di as err "map row `i': firstyear (`fys') exceeds lastyear (`lys')"
				exit 198
				}
			}
		clear
		}
	//Get all files in Directory//
	loc files:dir `"`directory'"' files "*.`filetype'" , nofail respectcase
		*-- Strip the extension and drop the output file, comparing WHOLE
		*-- tokens.  Do NOT run -subinstr- over the whole list: it deletes the
		*-- output stem wherever it appears INSIDE another filename, so an input
		*-- called mydata_2020.csv silently became data_2020.csv when the output
		*-- was named "my" -- that file was read twice and the real one never
		*-- read, with rc 0 and no warning.
		loc u2 `"`using2'"'
		loc _ux = strrpos(`"`u2'"', ".`filetype'")
		if `_ux' > 0 loc u2 = substr(`"`u2'"', 1, `_ux' - 1)
		loc keep ""
		foreach f of local files {
			loc stem `"`f'"'
			loc _fx = strrpos(`"`stem'"', ".`filetype'")
			if `_fx' > 0 loc stem = substr(`"`stem'"', 1, `_fx' - 1)
			if `"`stem'"' != `"`u2'"' loc keep `"`keep' "`stem'""'
		}
		loc files `"`keep'"'
	if `: word count `files'' == 0 {
		di as err `"no .`filetype' files found in `directory'"'
		exit 601
		}
	**extract the year from each filename and sort by year (map() only)**
	loc nfiles 0
	if `"`map'"' != "" {
		foreach f of local files {
			loc ++nfiles
			loc file`nfiles' `"`f'"'
			loc ystr ""
			if `"`year'"' == "" {
				* default: first 4-digit run starting 19 or 20
				if ustrregexm(`"`f'"', "(?<![0-9])((19|20)[0-9]{2})(?![0-9])") {
					loc ystr = ustrregexs(1)
					}
				}
			else if ustrregexm(`"`year'"', "^[0-9]+$") {
				* position spec: read 4 characters starting at that position
				loc ystr = substr(`"`f'"', `year', 4)
				}
			else {
				* custom regex; use capture group 1 when present, else the match
				if ustrregexm(`"`f'"', `"`year'"') {
					loc ystr = cond(ustrregexs(1) != "", ///
						ustrregexs(1), ustrregexs(0))
					}
				}
			cap confirm integer number `ystr'
			if _rc | length("`ystr'") != 4 {
				di as err `"could not extract a 4-digit year from "' ///
					`"filename `f'.`filetype' (got: "`ystr'"); use the year() option"'
				exit 198
				}
			loc fyear`nfiles' = real("`ystr'")
			}
		* sort files by year (name breaks ties), then rebuild the token list
		if `nfiles' > 1 {
			forval a = 1/`=`nfiles' - 1' {
				forval b = `=`a' + 1'/`nfiles' {
					if (`fyear`b'' < `fyear`a'') | ///
					   (`fyear`b'' == `fyear`a'' & `"`file`b''"' < `"`file`a''"') {
						loc tf `"`file`a''"'
						loc ty = `fyear`a''
						loc file`a' `"`file`b''"'
						loc fyear`a' = `fyear`b''
						loc file`b' `"`tf'"'
						loc fyear`b' = `ty'
						}
					}
				}
			}
		loc files ""
		forval j = 1/`nfiles' {
			loc files `"`files' "`file`j''""'
			}
		}
	**seed the output file (skipped under convertonly)**
	if `"`cmethod'"' != "convertonly" {
		qui set obs 1
		qui gen byte ___0seed = 1
		foreach vm in `mvars' {
			qui g `vm' = ""
			}
		qui sa "`using'.dta", replace
		}
	tokenize `"`files'"'
	loc _j 0
	loc nev 0              // rename events across all files (map only)
	loc nmiss 0            // expected-but-absent oldnames (map only)
	while `"`1'"' != "" {
		loc ++_j
		**file Input**
		if inlist(`"`filetype'"', "xls", "xlsx") {
				qui import excel using `"`directory'/`1'.`filetype'"', firstrow clear
			}
		else if inlist(`"`filetype'"', "xml") {
				clear
				qui xmluse `"`directory'/`1'.`filetype'"' , `xmlopts'
				}
		else if inlist(`"`filetype'"', "dta") {
				qui use `"`directory'/`1'.`filetype'"', clear
				}
		else {
				* csv, txt, raw, out, log, and any other extension are
				* read as delimited text (v2: import delimited, not insheet)
				* (v2.0.2: bindquote(strict) keeps a quoted field that
				* spans lines, such as a free-text answer, in one cell;
				* _cmb_qguard falls back to loose binding only when a
				* line inside such a cell looks like a data row, the
				* sign of a stray unmatched quote)
				_cmb_qguard `"`directory'/`1'.`filetype'"', ///
					asdouble `dddd' `strictquotes'
			}
		**vintage-window renames + year stamp (harmonization layer)**
		if `"`map'"' != "" {
			loc _yr = `fyear`_j''
			loc nren 0
			loc consumed ""
			forval i = 1/`nmap' {
				if `skip`i'' continue
				if !(`fy`i'' <= `_yr' & `_yr' <= `ly`i'') continue
				loc old `old`i''
				loc new `new`i''
				if `: list old in consumed' continue      // renamed already
				cap confirm variable `old', exact
				if !_rc {
					loc consumed `consumed' `old'
					if "`old'" != "`new'" {
						cap confirm variable `new', exact
						if !_rc {
							di as err "both `old' and `new' exist in " ///
								"`1'.`filetype' (year `_yr'); cannot rename"
							exit 110
							}
						rename `old' `new'
						loc ++nren
						loc ++nev
						loc evv`nev' `new'
						loc evs`nev' `"`old' (`1'.`filetype', `_yr')"'
						}
					}
				else {
					loc ++nmiss
					loc missmsg`nmiss' ///
						`"`old' (map row `i', -> `new') not found in `1'.`filetype' (year `_yr')"'
					if "`strict'" != "" {
						di as err `"`missmsg`nmiss'' -- strict specified"'
						exit 111
						}
					}
				}
			**stamp the year**
			cap confirm variable year, exact
			if !_rc {
				di as err "`1'.`filetype' already contains a variable named " ///
					"year; move it aside with a map row (e.g. year,year_src,,)"
				exit 110
				}
			qui gen int year = `_yr'
			}
		**fileid**
		if `"`fileid'"' != "" {
			cap drop `fileid'
			qui g `fileid' = "`1'.`filetype'"
			order `fileid'
			}
		**tostring**
		if `"`tostring'"' == "tostring" {
			qui ds
			foreach tsf in `r(varlist)' {
				qui  cap tostring `tsf', force replace u
				}
			}
		**save file**
		qui  sa  `"`directory'/`prefix'`1'`suffix'.dta"', replace
	**--combine method--**
	if `"`cmethod'"' != "convertonly" {
		if `"`cmethod'"' == "append" {
			qui u  "`using'.dta", clear
			qui append using `"`directory'/`prefix'`1'`suffix'.dta"', force `options'
			qui sa 	"`using'.dta", replace
			}
		if `"`cmethod'"' == "merge" {
			**for _merge:
			if `"`_merge'"' != "" loc _m_merge `"gen(_`1')"'
			qui u  "`using'.dta", clear
			qui cap drop _merge
			qui merge `mtype' `mvars' using `"`directory'/`prefix'`1'`suffix'.dta"', `_m_merge' `options'
			qui sa 	"`using'.dta", replace
			}
		if `"`cmethod'"' == "joinby" {
			**for joinby _merge var:
			if `"`_merge'"' != "" loc _j_merge `"_merge(_`1')"'
			qui u  "`using'.dta", clear
			qui cap drop _merge
			qui joinby  `mvars' using `"`directory'/`prefix'`1'`suffix'.dta"',  `_j_merge' `options'
			qui sa 	"`using'.dta", replace
			}
	} //cmethod convertonly loop
	**keep converted**
		if `"`keepconverted'"' != "keepconverted" & `"`filetype'"' != "dta" {
			cap qui rm  `"`directory'/`prefix'`1'`suffix'.dta"'
			}

	macro shift
	} //end while loop

**compress master data**
if `"`cmethod'"' != "convertonly" {
	qui u "`using'.dta", clear
	**remove the seed row and marker (v2: explicit ___0seed marker replaces
	**the v1.0.0 seed cleanup, which could drop real rows under joinby)**
	cap confirm variable ___0seed, exact
	if !_rc {
		qui drop if ___0seed == 1
		qui drop ___0seed
		}
		qui compress
	**provenance chars: char varname[source] "oldname (file, year)"**
	if `"`map'"' != "" {
		loc renfinal ""
		forval k = 1/`nev' {
			loc nn `evv`k''
			if !`: list nn in renfinal' loc renfinal `renfinal' `nn'
			}
		foreach v of local renfinal {
			loc s ""
			forval k = 1/`nev' {
				if "`evv`k''" == "`v'" {
					if `"`s'"' != "" loc s `"`s'; "'
					loc s `"`s'`evs`k''"'
					}
				}
			cap confirm variable `v', exact
			if !_rc char `v'[source] `"`s'"'
			}
		order year, first
		}
	qui sa "`using'.dta", replace
}

**results window output**
		noi di as txt as smcl `"Converted Files in Directory: {browse `"`directory'"'}"'
		if `"`cmethod'"' != "convertonly" noi di as txt as smcl `"Combined File: {stata desc using `"`using'.dta"':`using'.dta}"'

**harmonization table: variable x years present (map only)**
if `"`map'"' != "" & `"`cmethod'"' != "convertonly" {
	qui levelsof year, local(years)
	loc ny : word count `years'
	di as txt _n "Harmonization table (X = data present in that year):"
	if `ny' <= 16 {
		di as txt _n %-24s "variable" _c
		foreach y of local years {
			di as txt %6s "`y'" _c
			}
		di ""
		di as txt "{hline `= 24 + 6*`ny''}"
		foreach v of varlist _all {
			if "`v'" == "year" continue
			di as txt %-24s abbrev("`v'", 23) _c
			cap confirm string variable `v', exact
			loc isstr = (_rc == 0)
			foreach y of local years {
				if `isstr' qui count if `v' != "" & year == `y'
				else       qui count if !missing(`v') & year == `y'
				if r(N) > 0 di as res %6s "X" _c
				else        di as txt %6s "." _c
				}
			di ""
			}
		}
	else {
		foreach v of varlist _all {
			if "`v'" == "year" continue
			cap confirm string variable `v', exact
			loc isstr = (_rc == 0)
			loc present ""
			foreach y of local years {
				if `isstr' qui count if `v' != "" & year == `y'
				else       qui count if !missing(`v') & year == `y'
				if r(N) > 0 loc present "`present' `y'"
				}
			di as txt %-24s abbrev("`v'", 23) as res "`present'"
			}
		}
	**report (not error) any expected oldname that was absent**
	if `nmiss' > 0 {
		di as txt _n "Expected map variables absent (report only; " ///
			"strict makes this an error):"
		forval m = 1/`nmiss' {
			di as res "  `missmsg`m''"
			}
		}
	di as txt _n "combineall: " as res `_j' as txt " file(s), " ///
		as res `=_N' as txt " observations, " as res `=c(k)' ///
		as txt " variables, years " as res "`years'"
	}

**stored results**
return scalar n_files = `_j'
if `"`cmethod'"' != "convertonly" {
	return local output `"`using'.dta"'
	}
if `"`map'"' != "" & `"`cmethod'"' != "convertonly" {
	return scalar n_vars    = c(k)
	return scalar n_missing = `nmiss'
	return local  years     "`years'"
	}

restore
end

* ---------------------------------------------------------------------------
* _cmb_qguard: import a delimited file under the stray-quote rule.  The same
* helper, with the same logic, ships in combineall, cxchangelog and
* convertanything (only the _cmb_ name prefix differs).
*   1. Import once with bindquote(strict) maxquotedrows(unlimited), so a
*	  quoted field that spans lines stays one cell.
*   2. strictquotes: keep the strict result; no check, no fallback.
*   3. Fast path: if no string cell contains a line break, keep the strict
*	  result.  The file is read once and nothing is printed.
*   4. Otherwise split each cell that contains a line break at its line
*	  breaks.  A line after the first looks like a data row of this file
*	  when it holds at least k-1 delimiters (k = number of columns of the
*	  strict import).  When k <= 2 that is too weak, so the line must also
*	  start with an id-like token (digits, optionally after up to four
*	  letters and a _ or -, such as 17, Q12, id_003 or 2024-001) and the
*	  file's first column must hold such values.
*	  - Some line looks like a data row: an unmatched quote (such as the
*		inch mark in 5" screen) joined rows.  Warn, naming the file, the
*		row and column where the joined cell starts, and the strict and
*		loose row counts, then import again with the default loose binding
*		and keep that result.  This also holds when the file has genuine
*		multi-line fields as well: the stray-quote reading wins.
*	  - No line does: the breaks are genuine multi-line text.  Keep the
*		strict result and print nothing.
* Leaves in the caller: qg_status (clean, multiline, stray or forced),
* qg_nread (imports run, 1 or 2), qg_nstrict, qg_nloose, qg_k, qg_obs and
* qg_var.  nowarn suppresses the warning (the caller prints its own).
* ---------------------------------------------------------------------------
program define _cmb_qguard
	version 16
	gettoken fname 0 : 0, parse(" ,")
	syntax , [STRICTQuotes NOWARN DELIMiters(string asis) *]
	local dl `delimiters'
	if `"`delimiters'"' != "" local options `"`options' delimiters(`delimiters')"'
	c_local qg_status ""
	c_local qg_nloose ""
	c_local qg_obs ""
	c_local qg_var ""
	quietly import delimited using `"`macval(fname)'"', `options' ///
		bindquote(strict) maxquotedrows(unlimited) clear
	local nstrict = _N
	local k = c(k)
	c_local qg_nread 1
	c_local qg_nstrict `nstrict'
	c_local qg_k `k'
	if "`strictquotes'" != "" {
		c_local qg_status forced
		exit
	}
	mata: _cmb_qgscan(st_local("fname"), st_local("dl"))
	if "`qg_ml'" == "0" {
		c_local qg_status clean
		exit
	}
	if "`qg_hit'" == "0" {
		c_local qg_status multiline
		exit
	}
	quietly import delimited using `"`macval(fname)'"', `options' clear
	local nloose = _N
	c_local qg_status stray
	c_local qg_nread 2
	c_local qg_nloose `nloose'
	c_local qg_obs `qg_obs'
	c_local qg_var `qg_var'
	if "`nowarn'" == "" {
		di as err "warning:" as txt `" stray-quote check on file `fname'"'
		di as txt "  In the strict read, the quoted cell in row " as res `qg_obs' ///
			as txt ", column " as res "`qg_var'" as txt " runs on into lines"
		di as txt "  that look like data rows (each has at least " as res `k' - 1 ///
			as txt `" delimiter(s)): an unmatched quote, such as the inch mark in 5" screen, joined rows."'
		di as txt "  strict quote binding read " as res `nstrict' as txt ///
			" row(s); loose binding read " as res `nloose' as txt ///
			" row(s); using the loose result."
		di as txt "  If those lines are text inside one quoted field, " ///
			"specify {bf:strictquotes} to keep strict binding."
	}
end

mata:
// stray-quote rule (see _cmb_qguard): sets locals qg_ml (some string cell
// has a line break), qg_hit (some later line looks like a data row), and
// qg_obs/qg_var (the first such cell: lowest row, then leftmost column)
void _cmb_qgscan(string scalar fname, string scalar dl)
{
	real scalar k, j, i, r, anchor, bestr, bestj, found
	real vector ix
	string colvector s
	string scalar d

	st_local("qg_ml", "0")
	st_local("qg_hit", "0")
	k = st_nvar()
	bestr = bestj = .
	found = 0
	anchor = 1
	d = ","
	for (j = 1; j <= k; j++) {
		if (!st_isstrvar(j)) continue
		s = st_sdata(., j)
		ix = selectindex((strpos(s, char(10)) :+ strpos(s, char(13))) :> 0)
		if (length(ix) == 0) continue
		if (!found) {
			found = 1
			st_local("qg_ml", "1")
			d = _cmb_qgdelim(fname, dl, k)
			if (k <= 2) anchor = _cmb_qganchor()
		}
		if (!anchor) return
		for (i = 1; i <= length(ix); i++) {
			r = ix[i]
			if (r >= bestr) break
			if (_cmb_qgrowline(s[r], d, k)) {
				bestr = r
				bestj = j
				break
			}
		}
	}
	if (bestr < .) {
		st_local("qg_hit", "1")
		st_local("qg_obs", strofreal(bestr))
		st_local("qg_var", st_varname(bestj))
	}
}

// 1 if a line after the first line of cell c looks like a data row
real scalar _cmb_qgrowline(string scalar c, string scalar d, real scalar k)
{
	string scalar t, line
	real scalar p, first

	t = subinstr(c, char(13) + char(10), char(10))
	t = subinstr(t, char(13), char(10))
	first = 1
	while (1) {
		p = strpos(t, char(10))
		if (p) {
			line = substr(t, 1, p - 1)
			t = substr(t, p + 1, .)
		}
		else line = t
		if (!first) {
			if (_cmb_qgcount(line, d) >= k - 1) {
				if (k > 2) return(1)
				if (_cmb_qgidlike(_cmb_qglead(line, d, k))) return(1)
			}
		}
		first = 0
		if (!p) return(0)
	}
	return(0)
}

// the delimiter: delimiters() when given, else the candidate (comma, tab,
// semicolon, pipe) that splits the first line of the file into k fields,
// else the most frequent candidate on that line, else comma
string scalar _cmb_qgdelim(string scalar fname, string scalar dl, real scalar k)
{
	real scalar fh, j, n, best, bestn, p
	string scalar buf
	string rowvector cand

	if (dl == char(92) + "t") return(char(9))
	if (dl != "") return(dl)
	cand = (",", char(9), ";", "|")
	fh = _fopen(fname, "r")
	if (fh < 0) return(",")
	buf = fread(fh, 65536)
	fclose(fh)
	if (buf == J(0, 0, "")) return(",")
	if (substr(buf, 1, 3) == char(239) + char(187) + char(191)) buf = substr(buf, 4, .)
	p = strpos(buf, char(10))
	if (p) buf = substr(buf, 1, p - 1)
	p = strpos(buf, char(13))
	if (p) buf = substr(buf, 1, p - 1)
	best = 1
	bestn = 0
	for (j = 1; j <= cols(cand); j++) {
		n = _cmb_qgcount(buf, cand[j])
		if (k > 1 & n == k - 1) return(cand[j])
		if (n > bestn) {
			best = j
			bestn = n
		}
	}
	return(cand[best])
}

// number of delimiter characters in s (each character of d counts)
real scalar _cmb_qgcount(string scalar s, string scalar d)
{
	real scalar j, n
	n = 0
	for (j = 1; j <= strlen(d); j++) {
		n = n + strlen(s) - strlen(subinstr(s, substr(d, j, 1), ""))
	}
	return(n)
}

// the first field of a line (the whole line when k == 1)
string scalar _cmb_qglead(string scalar line, string scalar d, real scalar k)
{
	real scalar j, p, q
	if (k == 1) return(line)
	p = strlen(line) + 1
	for (j = 1; j <= strlen(d); j++) {
		q = strpos(line, substr(d, j, 1))
		if (q & q < p) p = q
	}
	return(substr(line, 1, p - 1))
}

// 1 if s is an id-like token: 17, Q12, id_003, 2024-001 (quotes allowed)
real scalar _cmb_qgidlike(string scalar s)
{
	string scalar t
	t = strtrim(s)
	if (strlen(t) >= 2 & substr(t, 1, 1) == char(34) & substr(t, -1, 1) == char(34)) {
		t = substr(t, 2, strlen(t) - 2)
	}
	return(ustrregexm(t, "^[A-Za-z]{0,4}[_-]?[0-9]+([._-][0-9]+)*$"))
}

// 1 if the first column holds id-like values (the file's row pattern,
// needed when k <= 2): any nonmissing number, or any string whose first
// line is id-like
real scalar _cmb_qganchor()
{
	real scalar i, p
	string colvector s
	string scalar t
	if (!st_isstrvar(1)) return(missing(st_data(., 1)) < st_nobs())
	s = st_sdata(., 1)
	for (i = 1; i <= rows(s); i++) {
		t = subinstr(s[i], char(13), char(10))
		p = strpos(t, char(10))
		if (p) t = substr(t, 1, p - 1)
		if (_cmb_qgidlike(t)) return(1)
	}
	return(0)
}
end
