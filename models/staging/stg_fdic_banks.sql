-- Thin staging pass over raw.fdic_active_banks_lean.
-- Renames: fdic_certificate_number -> fdic_cert (natural key alias used downstream).
-- Transforms: trim identity/name text; upper-case 2-char state code.
-- Deferred to later layers: top_holder normalization quirks (BCORP/BANCORP,
-- trailing THE, `&` spacing) belong in the crosswalk/intermediate layer.

with source as (
    select * from {{ source('raw', 'fdic_active_banks_lean') }}
),

renamed as (
    select
        trim(fdic_certificate_number)  as fdic_cert,
        trim(institution_name)         as institution_name,
        trim(trade_name_1)             as trade_name_1,
        fdic_id,
        rssd_id,
        ultimate_cert_number,
        parent_parcert,

        active,
        conservatorship,
        denovo_institute,

        trim(address)                  as address,
        trim(city)                     as city,
        upper(trim(state))             as state,
        state_name,
        state_fips_code,
        zip_code,
        county_name,
        county_fips_code,
        cbsa_name,
        cbsa_fips_code,
        cbsa_metro_flag,
        cbsa_micro_flag,
        cbsa_division_name,
        cbsa_division_fips_code,
        cbsa_division_flag,
        csa_name,
        csa_fips_code,
        csa_indicator,

        bank_charter_class,
        chartering_agency,
        federal_charter,
        state_chartered,
        occ_charter,
        occ_district,
        regulator,
        category_code,
        ots_region,
        qbp_region,
        fdic_geo_region,
        fdic_supervisory_region,
        fdic_supervisory_region_code,
        fdic_field_office,
        fed_reserve_district,
        fed_reserve_district_id,
        fed_reserve_unique_id,
        docket,

        cfpb_supervisory_flag,
        cfpb_supervisory_start_date,
        cfpb_supervisory_end_date,

        fdic_insured,
        deposit_insurance_date,
        deposit_insurance_fund_member,
        bank_insurance_fund_member,
        insurance_fund_membership,
        secondary_insurance_fund,
        insured_commercial_bank,
        insured_savings_institute,

        holding_company_flag,
        holding_company_state,
        trim(high_holder_city)         as high_holder_city,
        trim(top_holder)               as top_holder,
        ownership_type,
        subchap_s_indicator,

        primary_specialization,
        asset_concentration_hierarchy,
        credit_card_institution,
        ag_lending_flag,
        trust_powers_status,
        iba,
        ffiec_call_report_filer,
        law_sasser,

        total_assets,
        total_deposits,
        total_domestic_deposits,
        equity_capital,
        net_income,
        quarterly_net_income,
        return_on_assets,
        roa_quarterly,
        roa_pretax,
        row_pretax_quarterly,
        return_on_equity,
        roe_quarterly,

        offices_count,
        office_count_domestic,
        office_count_foreign,
        office_count_us_territories,

        established_date,
        last_structural_change,
        effective_date,
        end_effective_date,
        report_date,
        reporting_period_end_date,
        last_updated,
        run_date

    from source
)

select * from renamed
