# combineall — combine or convert every file in a directory

**A 2011 directory-combining engine with a 2026 harmonization layer: append, merge, joinby, or convert every file in a folder, and stack yearly vintages under a rename map.**

```stata
combineall using "built/panel", cmethod(append) directory("raw/") map("renames.csv")
```

## The story

`combineall` v1.0.0 shipped in April 2011 as a workhorse for a common chore: a folder full of files that all need to become one dataset. It converts text files (CSV and other delimited formats), Excel, and XML to `.dta`, then combines everything by `append`, `merge`, or `joinby`, or just converts and stops (`convertonly`). Options cover the practical details: a `fileid()` variable recording each row's source file, `_merge` match-status variables per file, `prefix()`/`suffix()` naming for converted copies, `tostring` for type-wobbly sources, and a `replace` guard so an existing output is never silently overwritten.

v2.0.0 (2026) keeps that engine and its option set, raises the floor to Stata 16, replaces the deprecated `insheet` with `import delimited` (and reads Excel properly with `import excel`), and grafts on the harmonization layer developed for the authors' applied-evaluation book. The problem it solves: agencies publish one file per year, and element names mutate across vintages. A column called one thing in 2015 is renamed by 2020, so a naive append stacks unrelated variables. With `map()`, `combineall` extracts the 4-digit year stamped in each filename, sorts the files by year, applies only the renames whose `[firstyear,lastyear]` window covers that year, generates `int year`, and appends everything into one harmonized panel.

Every rename is written down twice. The map CSV is the human-readable record of the harmonization decisions, and each renamed variable carries a characteristic, `char varname[source]`, recording the original name, source file, and year, so the panel documents its own provenance. After stacking, `combineall` prints a harmonization table (each final variable by the years in which it has data) and lists any file where a mapped `oldname` was expected but absent. That absence is a report, not an error, unless you ask for `strict`.

## Install

From GitHub:

```stata
net install combineall, from("https://raw.githubusercontent.com/ericabooth/combineall-stata-public/main/") replace force
help combineall
```

## Quick start

Both blocks below are self-contained and run as shown in an empty working directory. Stata does not create output folders on demand, so each block creates the folders it writes into first; `capture` lets a block be re-run after its folders exist.

The engine, without the layer — append every `.dta` file in a folder, tagging each row with its source:

```stata
capture mkdir "pieces"
capture mkdir "built"

sysuse auto, clear
keep make price mpg
save "pieces/part1.dta", replace
save "pieces/part2.dta", replace

combineall using "built/all.dta", cmethod(append) directory("pieces/") filetype(dta) fileid(srcfile) replace
```

Note that `filetype(dta)` with no `prefix()`/`suffix()` rewrites the sources in place, so this block leaves `srcfile` behind in `pieces/part1.dta` and `pieces/part2.dta`. Point a later command at a fresh folder rather than at `pieces/`.

The layer — build two tiny yearly files whose price column changes name, write a two-line map, and stack:

```stata
capture mkdir "raw"
capture mkdir "built"

sysuse auto, clear
keep make price mpg
export delimited using "raw/cars_2019.csv", replace
rename price price_usd
export delimited using "raw/cars_2020.csv", replace

file open m using "map.csv", write replace
file write m "oldname,newname,firstyear,lastyear" _n
file write m "price_usd,price,2020," _n
file close m

combineall using "built/cars_panel", cmethod(append) directory("raw/") map("map.csv") replace
use "built/cars_panel.dta", clear
char list price[source]
tabulate year
```

The map row reads: from 2020 onward (`firstyear` 2020, `lastyear` blank and so open-ended), `price_usd` is what `price` is called, so fold it back. The stacked panel has one `price` column across both years, and `char list price[source]` shows where the renamed values came from.

## Engine options (2011)

| Option | What it does |
|---|---|
| `cmethod(method)` | `append`, `merge`, `joinby`, or `convertonly` (default) |
| `directory(path)` | folder containing the input files (default: working directory) |
| `replace` | overwrite the `using` output file |
| `filetype(ext)` | extension swept up: `csv` (default), `dta`, `txt`, `xlsx`, `xls`, `xml`, or any text extension |
| `fileid(newvar)` | variable holding each observation's source filename |
| `mtype(type)` | merge type: `1:1` (default), `m:m`, `1:m`, `m:1` |
| `mvars(varlist)` | key variables for `merge`/`joinby` (required with those methods; keys must be strings) |
| `_merge` | one match-status variable per file, named `_filestem` |
| `delimiter(char)` | `comma` (default), `tab`, or a character such as `";"` |
| `prefix()` / `suffix()` | decorate converted filenames |
| `tostring` | convert every variable to string during conversion, using each variable's display format (lossy for numerics; see Limits) |
| `keepconverted` | keep the per-file converted `.dta` copies (implied by `convertonly`) |
| `xmlopts(options)` | options passed to `xmluse` |

## Harmonization options (v2.0.0, `cmethod(append)` only)

| Option | What it does |
|---|---|
| `map(renames.csv)` | the rename map; activates the layer (year extraction, vintage renames, `year` variable, `[source]` chars, harmonization table) |
| `year(spec)` | year extraction: a starting position (`year(14)`) or a regex with a capture group (`year("run_([0-9][0-9][0-9][0-9])")`); default is the first 4-digit run 19xx/20xx |
| `strict` | error (111) instead of report when a mapped `oldname` is absent from a covered file |

The map file is a plain CSV with a header row and four columns:

```
oldname,newname,firstyear,lastyear
enroll_cnt,enrollment,,2020
mscore,mathscore,2019,2019
```

Blank `firstyear` or `lastyear` leaves that end of the window open. A row whose `oldname` equals its `newname` asserts presence (useful with `strict`). Matching is exact and case-sensitive. Keep the map file outside `directory()`, or it will be swept up as an input.

## Stored results

| Result | Contents |
|---|---|
| `r(n_files)` | number of files converted/combined |
| `r(output)` | path of the combined file (not `convertonly`) |
| `r(n_vars)` | number of variables in the panel, including `year` (`map()` only) |
| `r(n_missing)` | number of expected-but-absent oldname reports (`map()` only) |
| `r(years)` | distinct years stacked, ascending (`map()` only) |

## Limits, stated plainly

- Output goes to the `using` file on disk; your data in memory are preserved and restored, not replaced.
- Appends use `force` (engine semantics since 2011), so a string/numeric type conflict across files coerces the offending values to missing instead of stopping. This holds under `map()` too, and differs from a bare `append`. Check the harmonization table for unexpected gaps.
- `tostring` is lossy for numerics. The conversion runs as `tostring varname, force replace usedisplayformat`, so each value is written as its display format renders it rather than at full precision: a double holding 1/3 under the default `%10.0g` becomes the string `.33333333`, and `destring` cannot recover the dropped digits. The conversion runs quietly, so `tostring`'s own loss-of-information message is not shown. Reserve `tostring` for identifier-like columns whose type wobbles across files.
- `merge`/`joinby` keys must be strings (the seeded empty master creates them as strings); `joinby` needs `unmatched(both)` to be useful.
- With `filetype(dta)` and no `prefix()`/`suffix()`, the converted copy is the source file itself, so `fileid()`, `tostring`, and `map()` renames write back into the sources.
- One year per file, taken from the filename; files containing multiple years should be split upstream.
- No subdirectory recursion.

## Lineage and license

combineall v1.0.0: April 2011, Eric A. Booth. v2.0.0: 2026, Eric A. Booth, Sr Researcher, Texas 2036 (eric.a.booth@gmail.com) and Elizabeth Teas, Sr Research Scientist, Far Harbor, LLC (elizabeth@farharbor.com). v2.0.0 replaces the short-lived `panelstack` package; its `map()`/`year()`/`strict` layer now lives here.

MIT. Copyright (c) 2026 Eric A. Booth. See [LICENSE](LICENSE).
