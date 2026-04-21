# Data Quality Notes — CFPB Complaint Database

Field-level notes on source quirks, CFPB publication rules, and known staging
limitations. Intended as a reference for model authors and interview discussion.

---

## ZIP Code

### CFPB privacy truncation rule (known limitation in staging)

CFPB intentionally publishes **3-digit ZIP codes** for a specific subset of complaints:
complaints where (a) the consumer consented to narrative publication AND (b) the consumer
lives in a ZIP code aligned to a ZCTA with fewer than 20,000 people. In those cases, a
3-digit ZIP is published if the 3-digit ZCTA has more than 20,000 people; otherwise no
ZIP is published at all. Standard 5-digit ZIPs are published for all other complaints.
(Source: CFPB field reference; Release 10, June 2015; Release 5, Nov 2013.)

**Staging bug**: The current `stg_cfpb_complaints.sql` ZIP cleanup expression — which
converts float-formatted strings (`'30349.0'`) to zero-padded 5-digit strings via
`SAFE_CAST` + `LPAD` — incorrectly expands intentional 3-digit ZIPs into fake 5-digit
ZIPs. For example, a CFPB-published `017` (raw: `17.0`) becomes `00017` after cleanup.
These fabricated values are numeric and pass the `zip_code_is_valid` regex (`^\d{5}$`),
so the flag does NOT catch them.

**Impact**: Affected rows are a small subset — only complaints with narrative consent in
low-population ZCTAs. They will appear as valid 5-digit ZIPs with leading zeros in
states where such ZIP prefixes don't exist (e.g., `00017` in a state that uses the `017`
prefix). Geographic analysis using these values will be silently wrong.

**Fix required**: Before `LPAD`, detect whether the integer value is in the range 1–999
(i.e., a 3-digit ZIP) and handle separately — either keep as 3-digit string or mark
`zip_code_is_valid = FALSE`. Defer until the geographic analysis layer is built.

**Additional note**: Release 20 (May 2023) updated all ZIP values using 2019 Census ZCTA
population estimates, which may have reclassified some complaints from 3-digit to 5-digit
(or vice versa). Our dataset is frozen at 2022, so this affects late-2022 complaints
that were refreshed before our extract.

### Other zip code artifacts (from exploration)

- Raw values are float-formatted (`30349.0`) — BigQuery CSV import artifact. Staging
  strips `.0` before casting.
- Some entries have a trailing `-` (user began typing ZIP+4). Staging strips this.
- 48 complaints (45 distinct strings) have genuinely corrupted ZIP values (mixed
  punctuation, embedded dashes). These correctly resolve to `zip_code_is_valid = FALSE`.
- No `XXXXX` masked values observed in this dataset, contrary to CFPB documentation
  suggesting masking is possible.

---

## `consumer_consent_provided` — Population Timing

CFPB's publication timing explains the higher blank (null) rate in recent complaints:

- **`Consent provided` / `Consent not provided`**: Populated 60 days after the complaint
  is sent to the company OR after the company files an optional public response, whichever
  comes first.
- **`N/A`**: Populated immediately for (a) complaints received before March 2015 (before
  the narrative feature launched) or (b) complaints where the narrative option was not
  available.
- **`Other`**: Complaint doesn't meet criteria for narrative publication.
- **Blank**: Appears until the 60-day window elapses — the primary explanation for why
  recent complaints have more nulls. Staging maps nulls to `'not-provided'`.

Our dataset is frozen through 2022, so complaints from late 2022 may not have reached
their 60-day window before the extract was taken. Treat `not-provided` in 2022 as "not
yet resolved" rather than "consumer did not engage."

---

## `tags` — Field Definition and Coverage

CFPB's precise definitions (from field reference):

- **Older American**: Submitter reports that the consumer is age 62 or older.
- **Servicemember**: Active duty, National Guard, Reservist, Veteran, or retiree — AND
  spouses or dependents of servicemembers.
- Combined tag (`Older American, Servicemember`) is always Older American–first.

**Coverage start**: Tags were added in CFPB Release 11, February 2016. Pre-2016
complaints have no tags regardless of the consumer's actual status. In our dataset
(2012–2022), 2012–2015 complaints are structurally null for `tags` — this is a CFPB
data collection gap, not a quality issue. Treat 2016 as the effective floor for any
analysis using `tags`.

Confirmed distinct values in dataset: `Servicemember` (216,614), `Older American`
(133,725), `Older American, Servicemember` (31,874). Use `LIKE '%Servicemember%'` and
`LIKE '%Older American%'` to parse all three values correctly.

---

## `consumer_disputed` — Discontinuation

CFPB officially discontinued this field on April 24, 2017 (confirmed by Release 13,
May 2017 and Release 14, Nov 2017). From that date forward, complaints receive `N/A`.

Fill pattern in our dataset:
- 2012–2016: 100% filled
- 2017: 29.8% filled (partial year before cutoff)
- 2018–2022: 0% filled

Gate any dispute-rate metric on `date_received < '2017-04-24'` (or conservatively
`< '2017-01-01'`) to avoid comparing full-coverage years against empty ones.

---

## Date Ordering Violations (`date_received` vs `date_sent_to_company`)

7,036 rows (~0.2%) where `date_sent_to_company < date_received` by exactly 1 day. All
fall between 2012-01-22 and 2014-04-26 and are proportionally spread across major filers.
Conclusion: systematic intake-system artifact (timezone/batch-processing clock issue), not
a data error. Rows are kept; `assert_complaint_dates_ordered` runs at `severity: warn`.

---

## `days_to_company` = 0 (Not an Artifact)

High zero-day rate for `date_sent_to_company - date_received` is real: CFPB progressively
automated same-day routing. By 2020+, 92% of complaints are forwarded same-day. This
metric measures CFPB routing speed, not company resolution time.
