* test_combineall.do -- test battery for combineall v2.0.3
* Run:  stata-mp -b do test_combineall.do ["/path/to/pkg" ["/work/dir"]]
*   arg 1: folder holding combineall.ado (default: the working directory
*          when it holds combineall.ado, else found on the adopath)
*   arg 2: folder for the fixtures (default: c(tmpdir)); a subfolder
*          combineall_test is created there and removed at the end
* All paths live in globals set here; nothing below is hard-coded.

clear all
set more off
set seed 20260706

* ------------------------------------------------------------------ *
* Globals: package folder and scratch tree                            *
* ------------------------------------------------------------------ *
global pkgroot ""
if `"`1'"' != "" global pkgroot `"`1'"'
if `"$pkgroot"' == "" {
    capture confirm file "`c(pwd)'/combineall.ado"
    if !_rc global pkgroot `"`c(pwd)'"'
}
if `"$pkgroot"' == "" {
    capture findfile combineall.ado
    if !_rc {
        local fp `"`r(fn)'"'
        local s = max(strrpos(`"`fp'"', "/"), strrpos(`"`fp'"', "\"))
        if `s' > 1 global pkgroot = substr(`"`fp'"', 1, `s' - 1)
    }
}
if `"$pkgroot"' == "" {
    di as err "test_combineall: cannot locate combineall.ado; pass its folder as argument 1"
    exit 601
}
confirm file "$pkgroot/combineall.ado"
local work `"`2'"'
if `"`work'"' == "" local work `"`c(tmpdir)'"'
mata: st_local("work", subinstr(st_local("work"), char(92), "/"))
if substr(`"`work'"', -1, 1) == "/" local work = substr(`"`work'"', 1, strlen(`"`work'"') - 1)
global T "`work'/combineall_test"

* ++ prepends: the packaged v2.0.0 must shadow any older combineall
* (e.g., a 2011 copy in the PERSONAL ado path)
adopath ++ "$pkgroot"
which combineall

* ------------------------------------------------------------------ *
* 0. Build a clean scratch tree under the system tempdir              *
* ------------------------------------------------------------------ *
capture mkdir "$T"
foreach sub in conv dtaapp data pos mrg out bad tok tok2 ts ml sq both tab k2 {
    capture mkdir "$T/`sub'"
    local stale : dir "$T/`sub'" files "*"
    foreach f of local stale {
        erase "$T/`sub'/`f'"
    }
}
local stale : dir "$T" files "*"
foreach f of local stale {
    erase "$T/`f'"
}

* ------------------------------------------------------------------ *
* 1. convertonly: a tempdir of generated CSVs becomes .dta copies     *
* ------------------------------------------------------------------ *
forvalues k = 1/3 {
    clear
    set obs 4
    gen int id       = _n
    gen double v`k'  = _n * `k'
    export delimited using "$T/conv/c`k'.csv", replace
}

combineall, cmethod(convertonly) directory("$T/conv") prefix(z)
assert r(n_files) == 3
forvalues k = 1/3 {
    confirm file "$T/conv/zc`k'.dta"
}
use "$T/conv/zc2.dta", clear
assert _N == 4
confirm variable id v2
quietly summarize v2
assert r(mean) == 5                    // (2+4+6+8)/4

* ------------------------------------------------------------------ *
* 2. append of generated .dta files, with fileid()                    *
* ------------------------------------------------------------------ *
clear
set obs 5
gen int id    = _n
gen double a  = 10 * _n
quietly save "$T/dtaapp/f1.dta"

clear
set obs 3
gen int id    = _n + 5
gen double a  = 100 * _n
quietly save "$T/dtaapp/f2.dta"

combineall using "$T/out/append1", cmethod(append) ///
    directory("$T/dtaapp") filetype(dta) fileid(srcfile)
assert r(n_files) == 2
use "$T/out/append1.dta", clear
assert _N == 8
confirm variable id a srcfile
quietly count if srcfile == "f1.dta"
assert r(N) == 5
quietly count if srcfile == "f2.dta"
assert r(N) == 3
quietly summarize a if srcfile == "f2.dta" & id == 8
assert r(mean) == 300                  // 100 * 3

* ------------------------------------------------------------------ *
* 3. clobber/replace guard: rerun without replace errors (198),       *
*    rerun with replace succeeds                                      *
* ------------------------------------------------------------------ *
capture noisily combineall using "$T/out/append1", cmethod(append) ///
    directory("$T/dtaapp") filetype(dta)
assert _rc == 198

combineall using "$T/out/append1", cmethod(append) ///
    directory("$T/dtaapp") filetype(dta) replace
use "$T/out/append1.dta", clear
assert _N == 8

* ------------------------------------------------------------------ *
* 4. append with map(): the panelstack vintage-rename test            *
*    enroll_cnt (2019-2020) becomes enrollment in 2021;               *
*    mscore (2019 only) becomes mathscore in 2020;                    *
*    attend_rate exists in 2020 only but its map window is 2020-2021, *
*    so 2021 must produce a report (and an error under strict).       *
* ------------------------------------------------------------------ *
* 2019: 5 campuses
clear
set obs 5
gen int campus     = _n
gen int enroll_cnt = 100 * campus
gen double mscore  = 50 + campus
export delimited using "$T/data/enr_2019.csv", replace

* 2020: 6 campuses
clear
set obs 6
gen int campus         = _n
gen int enroll_cnt     = 200 * campus
gen double mathscore   = 60 + campus
gen double attend_rate = 0.90 + campus/100
export delimited using "$T/data/enr_2020.csv", replace

* 2021: 7 campuses, already uses the final names
clear
set obs 7
gen int campus       = _n
gen int enrollment   = 300 * campus
gen double mathscore = 70 + campus
export delimited using "$T/data/enr_2021.csv", replace

* the rename map (blank firstyear/lastyear = open-ended);
* kept OUTSIDE $T/data so it is not swept up as an input file
tempname m
file open `m' using "$T/map.csv", write replace
file write `m' "oldname,newname,firstyear,lastyear" _n
file write `m' "enroll_cnt,enrollment,,2020" _n
file write `m' "mscore,mathscore,2019,2019" _n
file write `m' "attend_rate,attendance,2020,2021" _n
file close `m'

combineall using "$T/out/panel", cmethod(append) ///
    directory("$T/data") map("$T/map.csv")
local nf   = r(n_files)
local nv   = r(n_vars)
local nmis = r(n_missing)
local yrs  "`r(years)'"

assert `nf' == 3
assert `nv' == 5                       // year campus enrollment mathscore attendance
assert `nmis' == 1                     // attend_rate absent from 2021 file
assert "`yrs'" == "2019 2020 2021"

use "$T/out/panel.dta", clear
assert _N == 18                        // 5 + 6 + 7

* year variable: stamped, int, correct per-file counts
confirm variable year
assert "`: type year'" == "int"
quietly count if year == 2019
assert r(N) == 5
quietly count if year == 2020
assert r(N) == 6
quietly count if year == 2021
assert r(N) == 7

* harmonized names: new names exist, old names are gone
confirm variable campus enrollment mathscore attendance
capture confirm variable enroll_cnt
assert _rc == 111
capture confirm variable mscore
assert _rc == 111
capture confirm variable attend_rate
assert _rc == 111

* predict-then-check values straight from the generating formulas
assert !missing(enrollment)
quietly summarize enrollment if year == 2019 & campus == 3
assert r(mean) == 300                  // 100 * 3
quietly summarize enrollment if year == 2020 & campus == 6
assert r(mean) == 1200                 // 200 * 6
quietly summarize enrollment if year == 2021 & campus == 7
assert r(mean) == 2100                 // 300 * 7
quietly summarize mathscore if year == 2019 & campus == 1
assert r(mean) == 51                   // 50 + 1
quietly count if !missing(attendance)
assert r(N) == 6                       // 2020 rows only
quietly count if !missing(attendance) & year != 2020
assert r(N) == 0

* provenance chars (saved into the output .dta)
local src : char enrollment[source]
assert strpos(`"`src'"', "enroll_cnt (enr_2019.csv, 2019)") > 0
assert strpos(`"`src'"', "enroll_cnt (enr_2020.csv, 2020)") > 0
local src : char mathscore[source]
assert `"`src'"' == "mscore (enr_2019.csv, 2019)"
local src : char attendance[source]
assert `"`src'"' == "attend_rate (enr_2020.csv, 2020)"

* ------------------------------------------------------------------ *
* 5. year() as a position spec and as a custom regex                  *
*    Default regex would grab 2020 first; position 14 reads 2019.     *
* ------------------------------------------------------------------ *
clear
set obs 4
gen int campus     = _n
gen int enroll_cnt = 10 * campus
export delimited using "$T/pos/batch2020run_2019.csv", replace

combineall using "$T/out/pos", cmethod(append) ///
    directory("$T/pos") map("$T/map.csv") year(14)
assert r(n_files) == 1
assert "`r(years)'" == "2019"
use "$T/out/pos.dta", clear
assert _N == 4
confirm variable enrollment            // 2019 is inside the map window

combineall using "$T/out/pos", cmethod(append) directory("$T/pos") ///
    map("$T/map.csv") year("run_([0-9][0-9][0-9][0-9])") replace
assert "`r(years)'" == "2019"

* ------------------------------------------------------------------ *
* 6. merge path on two generated files with mvars() and _merge        *
*    (merge keys must be strings: the seed master creates them so)    *
* ------------------------------------------------------------------ *
clear
set obs 4
gen str5 code = "k" + string(_n)
gen double x1 = _n
quietly save "$T/mrg/m1.dta"

clear
set obs 4
gen str5 code = "k" + string(_n)
gen double x2 = 10 * _n
quietly save "$T/mrg/m2.dta"

combineall using "$T/out/merged", cmethod(merge) ///
    directory("$T/mrg") filetype(dta) mvars(code) _merge
assert r(n_files) == 2
use "$T/out/merged.dta", clear
assert _N == 4
confirm variable code x1 x2 _m1 _m2
assert x2 == 10 * x1
assert _m1 == 2                        // rows arrived from m1.dta
assert _m2 == 3                        // and matched m2.dta

* ------------------------------------------------------------------ *
* 7. Deliberate error cases                                           *
* ------------------------------------------------------------------ *
* 7a. strict: attend_rate absent from the 2021 CSV -> r(111)
capture noisily combineall using "$T/out/strictout", cmethod(append) ///
    directory("$T/data") map("$T/map.csv") strict
assert _rc == 111
capture erase "$T/out/strictout.dta"   // partial output from the aborted run

* 7b. harmonization options require cmethod(append) -> r(198)
capture noisily combineall using "$T/out/badgraft", cmethod(merge) ///
    directory("$T/mrg") filetype(dta) mvars(code) map("$T/map.csv")
assert _rc == 198

* 7c. year()/strict without map() -> r(198)
capture noisily combineall using "$T/out/badgraft2", cmethod(append) ///
    directory("$T/data") year(14)
assert _rc == 198

* 7d. no files of the requested type -> r(601)
capture noisily combineall using "$T/out/none", cmethod(append) ///
    directory("$T/bad")
assert _rc == 601

* ------------------------------------------------------------------ *
* 8. File-list construction: the output stem and the file extension   *
*    are matched as WHOLE tokens, never stripped as substrings.       *
* ------------------------------------------------------------------ *
* 8a. Output stem "my" excludes my.csv only.  The pre-v2.0.1 engine
*     ran subinstr over the whole file list, so mydata.csv silently
*     became data.csv: the wrong file was read, with rc 0 and no warning.
clear
set obs 2
gen int id  = _n
gen str12 who = "my"
export delimited using "$T/tok/my.csv", replace

clear
set obs 3
gen int id  = _n
gen str12 who = "mydata"
export delimited using "$T/tok/mydata.csv", replace

combineall using "$T/tok/my", cmethod(append) ///
    directory("$T/tok") fileid(srcfile) replace
assert r(n_files) == 1                 // my.csv is the output, mydata.csv is not
use "$T/tok/my.dta", clear
assert _N == 3                         // mydata.csv only
levelsof srcfile, local(sf) clean
assert "`sf'" == "mydata.csv"
levelsof who, local(wh) clean
assert "`wh'" == "mydata"

* 8b. The extension string appearing INSIDE a filename must survive:
*     mycsvdata.csv and my.csvdata.csv are distinct inputs under
*     filetype(csv), and only the trailing ".csv" is stripped.
clear
set obs 2
gen int id  = _n
gen str12 who = "mycsvdata"
export delimited using "$T/tok2/mycsvdata.csv", replace

clear
set obs 3
gen int id  = _n
gen str12 who = "dotcsvdata"
export delimited using "$T/tok2/my.csvdata.csv", replace

combineall using "$T/out/tok2out", cmethod(append) ///
    directory("$T/tok2") fileid(srcfile) replace
assert r(n_files) == 2
use "$T/out/tok2out.dta", clear
assert _N == 5                         // 2 + 3
levelsof srcfile, local(sf) clean
assert "`sf'" == "my.csvdata.csv mycsvdata.csv"
levelsof who, local(wh) clean
assert "`wh'" == "dotcsvdata mycsvdata"

* ------------------------------------------------------------------ *
* 9. tostring uses the display format, and so is lossy for numerics.  *
*    A double holding 1/3 under %10.0g becomes the string ".33333333";*
*    the help documents this under the tostring option.               *
* ------------------------------------------------------------------ *
clear
set obs 3
gen double third = _n/3
export delimited using "$T/ts/nums.csv", replace

combineall, cmethod(convertonly) directory("$T/ts") prefix(t) tostring
assert r(n_files) == 1
use "$T/ts/tnums.dta", clear
assert substr("`: type third'", 1, 3) == "str"
assert third[1] == ".33333333"         // not 1/3 to full double precision
assert third[2] == ".66666667"

* ------------------------------------------------------------------ *
* 10. A bare combineall (no comma, no options) is legal: convertonly  *
*     over the .csv files in the working directory.  The syntax       *
*     diagram in the help shows the comma inside the brackets.        *
* ------------------------------------------------------------------ *
local cwd "`c(pwd)'"
cd "$T/conv"
combineall
assert r(n_files) == 3
confirm file "c1.dta"
confirm file "c3.dta"
cd "`cwd'"

* ------------------------------------------------------------------ *
* 10b-10g. The stray-quote rule (v2.0.2).  Delimited files are read  *
*      with bindquote(strict).  When a cell has a line break and a    *
*      later line of that cell looks like a data row (at least k-1    *
*      delimiters; for k <= 2 also an id-like leading token), a stray *
*      quote joined rows: combineall warns and uses loose binding.    *
*      Otherwise strict is kept silently.  The checks read warnings   *
*      from text logs and call the private helper _cmb_qguard to      *
*      count imports (r-free: it leaves qg_* locals).                 *
* ------------------------------------------------------------------ *
capture program drop _ca_countin
program define _ca_countin, rclass
    args fn needle
    mata: st_numscalar("r(hits)", ///
        sum(strpos(cat(st_local("fn")), st_local("needle")) :> 0))
    return scalar hits = r(hits)
end

* The helper is private to combineall.ado; running the file defines it
* for this do-file (discard first, so nothing is defined twice)
discard
capture program drop combineall _cmb_qguard _cmb_hdrchk
quietly run "$pkgroot/combineall.ado"

local ls0 = c(linesize)
set linesize 255                  // keep each warning line on one log line

* 10b. A legitimate multi-line survey answer stays one row by default,
*      with no warning and one import.  Without bindquote(strict) the row
*      split in two, the header became data, and the variables came back
*      as v1 v2.
clear
set obs 3
gen int id = _n
gen str80 comment = "first answer"
replace comment = "line one" + char(10) + "line two, and more" in 2
replace comment = "third answer" in 3
export delimited using "$T/ml/survey_2021.csv", quote replace
quietly import delimited using "$T/ml/survey_2021.csv", asdouble clear
assert _N > 3                        // loose binding splits the answer
quietly log using "$T/out/w_ml.log", text replace name(wml)
combineall using "$T/out/ml", cmethod(append) directory("$T/ml") replace
quietly log close wml
use "$T/out/ml.dta", clear
assert _N == 3
confirm variable id comment
assert comment[2] == "line one" + char(10) + "line two, and more"
assert comment[3] == "third answer"
_ca_countin "$T/out/w_ml.log" "warning:"
assert r(hits) == 0
_cmb_qguard "$T/ml/survey_2021.csv", asdouble delimiters(",")
assert "`qg_status'" == "multiline" & `qg_nread' == 1 & _N == 3
* strictquotes gives the same result; strictq is the minimum
* abbreviation; strict alone still means strict (which requires map())
combineall using "$T/out/ml", cmethod(append) directory("$T/ml") ///
    strictq replace
use "$T/out/ml.dta", clear
assert _N == 3
capture combineall using "$T/out/ml", cmethod(append) directory("$T/ml") ///
    strict replace
assert _rc == 198

* 10c. A stray unmatched quote (an inch mark).  Strict binding alone
*      folds rows 2-3 into one cell (_N 3 -> 1); the rule finds data-row
*      lines inside that cell, warns, and keeps the three loose rows.
file open fh using "$T/sq/inch_2020.csv", write replace text
file write fh "id,desc,n" _n
file write fh `"1,5" screen,10"' _n
file write fh "2,ok,20" _n
file write fh "3,fine,30" _n
file close fh
quietly import delimited using "$T/sq/inch_2020.csv", ///
    bindquote(strict) maxquotedrows(unlimited) clear
assert _N == 1                       // the failure the rule exists for
quietly log using "$T/out/w_sq.log", text replace name(wsq)
combineall using "$T/out/sq", cmethod(append) directory("$T/sq") replace
quietly log close wsq
use "$T/out/sq.dta", clear
assert _N == 3
assert id == _n
* rows 2-3 are intact; loose binding runs the stray-quote cell to the end
* of its own line, so that one line still needs repair upstream
assert n[2] == 20 & n[3] == 30
assert desc[2] == "ok" & desc[3] == "fine"
assert desc[1] == `"5" screen,10"' & missing(n[1])
_ca_countin "$T/out/w_sq.log" "warning:"
assert r(hits) == 1
_ca_countin "$T/out/w_sq.log" "stray-quote check on file $T/sq/inch_2020.csv"
assert r(hits) == 1
_ca_countin "$T/out/w_sq.log" "In the strict read, the quoted cell in row 1, column desc runs on into lines"
assert r(hits) == 1
_ca_countin "$T/out/w_sq.log" "strict quote binding read 1 row(s); loose binding read 3 row(s); using the loose result."
assert r(hits) == 1
quietly _cmb_qguard "$T/sq/inch_2020.csv", asdouble delimiters(",") nowarn
assert "`qg_status'" == "stray" & `qg_nread' == 2 & _N == 3
assert "`qg_obs'" == "1" & "`qg_var'" == "desc"
assert `qg_nstrict' == 1 & `qg_nloose' == 3
* strictquotes forces strict binding with no fallback (the swallowed result)
quietly log using "$T/out/w_sq2.log", text replace name(wsq2)
combineall using "$T/out/sq", cmethod(append) directory("$T/sq") ///
    strictquotes replace
quietly log close wsq2
use "$T/out/sq.dta", clear
assert _N == 1
_ca_countin "$T/out/w_sq2.log" "warning:"
assert r(hits) == 0

* 10d. A clean file (no line break in any cell): no warning, and the
*      fast path imports it once
quietly log using "$T/out/w_ok.log", text replace name(wok)
combineall using "$T/out/ok", cmethod(append) directory("$T/conv") replace
quietly log close wok
_ca_countin "$T/out/w_ok.log" "warning:"
assert r(hits) == 0
local okf : dir "$T/conv" files "*.csv"
gettoken okf : okf
_cmb_qguard "$T/conv/`okf'", asdouble delimiters(",")
assert "`qg_status'" == "clean" & `qg_nread' == 1

* 10e. Both in one file: a stray quote and a legitimate quoted line break.
*      Documented rule: the stray-quote warning wins, so the loose result
*      is kept (the multi-line answer splits too); strictquotes keeps the
*      strict result.  Neither is right: such a file must be fixed upstream.
file open fh using "$T/both/mix_2021.csv", write replace text
file write fh "id,desc,n" _n
file write fh `"1,"line one"' _n
file write fh `"line two",10"' _n
file write fh `"2,5" screen,20"' _n
file write fh "3,fine,30" _n
file write fh "4,ok,40" _n
file close fh
quietly import delimited using "$T/both/mix_2021.csv", asdouble clear
local nloose = _N
quietly import delimited using "$T/both/mix_2021.csv", asdouble ///
    bindquote(strict) maxquotedrows(unlimited) clear
local nstrict = _N
assert `nloose' > `nstrict'
quietly log using "$T/out/w_both.log", text replace name(wboth)
combineall using "$T/out/both", cmethod(append) directory("$T/both") replace
quietly log close wboth
use "$T/out/both.dta", clear
assert _N == `nloose'
_ca_countin "$T/out/w_both.log" "warning:"
assert r(hits) == 1
_ca_countin "$T/out/w_both.log" "In the strict read, the quoted cell in row 2, column desc"
assert r(hits) == 1
_ca_countin "$T/out/w_both.log" "strict quote binding read `nstrict' row(s); loose binding read `nloose' row(s)"
assert r(hits) == 1
combineall using "$T/out/both", cmethod(append) directory("$T/both") ///
    strictquotes replace
use "$T/out/both.dta", clear
assert _N == `nstrict'

* 10f. Tab-delimited variants (filetype(txt) delimiter(tab)).  A tab file's
*      multi-line answer with commas stays one row; a stray inch mark warns.
file open fh using "$T/tab/ml_2021.txt", write replace text
file write fh "id" _tab "comment" _tab "n" _n
file write fh "1" _tab `""one, two, three"' _n
file write fh `"four, five, six""' _tab "10" _n
file write fh "2" _tab "ok" _tab "20" _n
file close fh
quietly log using "$T/out/w_tab.log", text replace name(wtab)
combineall using "$T/out/tab", cmethod(append) directory("$T/tab") ///
    filetype(txt) delimiter(tab) replace
quietly log close wtab
use "$T/out/tab.dta", clear
assert _N == 2
assert comment[1] == "one, two, three" + char(10) + "four, five, six"
_ca_countin "$T/out/w_tab.log" "warning:"
assert r(hits) == 0
erase "$T/tab/ml_2021.txt"
file open fh using "$T/tab/inch_2020.txt", write replace text
file write fh "id" _tab "desc" _tab "n" _n
file write fh "1" _tab `"5" screen"' _tab "10" _n
file write fh "2" _tab "ok" _tab "20" _n
file write fh "3" _tab "fine" _tab "30" _n
file close fh
quietly log using "$T/out/w_tab2.log", text replace name(wtab2)
combineall using "$T/out/tab", cmethod(append) directory("$T/tab") ///
    filetype(txt) delimiter(tab) replace
quietly log close wtab2
use "$T/out/tab.dta", clear
assert _N == 3 & n[3] == 30
_ca_countin "$T/out/w_tab2.log" "strict quote binding read 1 row(s); loose binding read 3 row(s)"
assert r(hits) == 1

* 10g. Two columns (k = 2): a later line needs an id-like leading token
*      as well as one delimiter.  Free text with a comma stays one cell;
*      a stray quote that swallows "2,ok" rows is caught.
file open fh using "$T/k2/ml_2021.csv", write replace text
file write fh "id,comment" _n
file write fh `"1,"we waited"' _n
file write fh `"2 weeks, then left""' _n
file write fh "2,ok" _n
file close fh
combineall using "$T/out/k2", cmethod(append) directory("$T/k2") replace
use "$T/out/k2.dta", clear
assert _N == 2
assert comment[1] == "we waited" + char(10) + "2 weeks, then left"
erase "$T/k2/ml_2021.csv"
file open fh using "$T/k2/inch_2020.csv", write replace text
file write fh "id,comment" _n
file write fh `"1,5" screen"' _n
file write fh "2,ok" _n
file write fh "3,fine" _n
file close fh
quietly log using "$T/out/w_k2.log", text replace name(wk2)
combineall using "$T/out/k2", cmethod(append) directory("$T/k2") replace
quietly log close wk2
use "$T/out/k2.dta", clear
assert _N == 3
_ca_countin "$T/out/w_k2.log" "strict quote binding read 1 row(s); loose binding read 3 row(s)"
assert r(hits) == 1
set linesize `ls0'

* ------------------------------------------------------------------ *
* 10h. v2.0.3: all-text columns keep their header row; a header-less  *
*      numeric file still reads as v1, v2, ...; rep abbreviates       *
*      replace; the default output path has no doubled slash          *
* ------------------------------------------------------------------ *
capture mkdir "$T/hdr"
capture mkdir "$T/hdrn"
file open fh using "$T/hdr/a_2019.csv", write replace text
file write fh "name,city" _n "ann,austin" _n
file close fh
file open fh using "$T/hdr/b_2020.csv", write replace text
file write fh "name,city" _n "bob,waco" _n
file close fh
combineall using "$T/out/hdr", cmethod(append) directory("$T/hdr") replace
use "$T/out/hdr.dta", clear
assert _N == 2
confirm string variable name city
assert inlist(name, "ann", "bob")
* map() renames now match an all-text header
file open fh using "$T/hdrmap.csv", write replace text
file write fh "oldname,newname,firstyear,lastyear" _n "city,town,2020," _n
file close fh
combineall using "$T/out/hdrm", cmethod(append) directory("$T/hdr") ///
    map("$T/hdrmap.csv") replace
use "$T/out/hdrm.dta", clear
assert _N == 2
assert town == "waco" if year == 2020
assert city == "austin" if year == 2019
* rep is the documented abbreviation of replace
combineall using "$T/out/hdr", cmethod(append) directory("$T/hdr") rep
assert r(n_files) == 2
* a header-less all-number file still reads as data
file open fh using "$T/hdrn/n_2019.csv", write replace text
file write fh "1,2" _n "3,4" _n
file close fh
combineall using "$T/out/hdrn", cmethod(append) directory("$T/hdrn") replace
use "$T/out/hdrn.dta", clear
assert _N == 2
confirm numeric variable v1 v2
* a header-only all-text file gives names and no rows
file open fh using "$T/hdrn/h_2020.csv", write replace text
file write fh "alpha,beta" _n
file close fh
combineall using "$T/out/hdrn2", cmethod(convertonly) directory("$T/hdrn") ///
    filetype(csv)
use "$T/hdrn/h_2020.dta", clear
assert _N == 0
confirm variable alpha beta
* default output: directory() with a trailing slash, no doubled slash
combineall, cmethod(append) directory("$T/hdr/")
assert strpos(`"`r(output)'"', "//") == 0
confirm file "$T/hdr/combineall_output.dta"

* ------------------------------------------------------------------ *
* 11. Clean up the scratch tree                                       *
* ------------------------------------------------------------------ *
clear
foreach sub in conv dtaapp data pos mrg out bad tok tok2 ts ml sq both tab k2 hdr hdrn {
    local stale : dir "$T/`sub'" files "*"
    foreach f of local stale {
        erase "$T/`sub'/`f'"
    }
    rmdir "$T/`sub'"
}
local stale : dir "$T" files "*"
foreach f of local stale {
    erase "$T/`f'"
}
rmdir "$T"

di as txt _n "test_combineall.do: all asserts passed"
