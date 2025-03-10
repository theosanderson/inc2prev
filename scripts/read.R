library(dplyr)
library(data.table)
library(readr)
library(here)
library(tidyr)
library(socialmixr)

ons_to_nhse_region <- function(x) {
  recode(
    x,
    `North East` = "North East and Yorkshire",
    `Yorkshire and The Humber` = "North East and Yorkshire",
    `East Midlands` = "Midlands",
    `West Midlands` = "Midlands",
  )
}

read_cis <-
  function(fill_missing = TRUE, nhse_regions = TRUE,
           max_publication_date = NULL) {
  pops <- read_pop()
  ## get prevalence by ONS region
  prev_regional <- readr::read_csv(here::here("data-processed", "cis.csv")) %>%
    filter(level != "local") %>%
    left_join(pops %>%
      filter(level != "age_school") %>%
      select(level, geography_code, population),
      by = c("level", "geography_code")
    )
  ## get local prevalence, filling with ONS region estimates where missing
  prev_local <- readr::read_csv(here::here("data-processed", "cis.csv")) %>%
    filter(level == "local")
  if (fill_missing) {
    missing_dates_local <- seq(
      as.Date("2021-03-21"), as.Date("2021-06-27"),
      by = 7
    )
    additional_dates <-
      expand_grid(
        level = "local",
        geography_code = unique(prev_local$geography_code),
        start_date = missing_dates_local
      ) %>%
      mutate(end_date = start_date + 6) %>%
      inner_join(prev_local %>%
        select(level, geography, geography_code, region) %>%
        distinct(),
        by = c("level", "geography_code")
      ) %>%
      inner_join(prev_regional %>%
        select(start_date,
          region = geography,
          starts_with("proportion")
        ))
    prev_local <- prev_local %>%
      bind_rows(additional_dates) %>%
      arrange(geography_code, start_date)
  }
  prev_regional <- prev_regional %>%
    select(level,
      publication_date,
      start_date,
      end_date,
      middle = proportion_pos,
      lower = proportion_pos_low_95,
      upper = proportion_pos_high_95,
      variable = geography,
      population
    )
  ## convert retional prevalence to NHSE regional prevalence
  if (nhse_regions) {
    prev_regional <- prev_regional %>%
      mutate(variable = ons_to_nhse_region(variable)) %>%
      pivot_longer(c(middle, lower, upper)) %>%
      group_by(
        level, publication_date, start_date, end_date, variable, name
      ) %>%
      summarise(
        value = sum(population * value) / sum(population),
        population = sum(population),
        .groups = "drop"
      ) %>%
      pivot_wider()
  }
  ## finalise local prevalence
  prev_local <- prev_local %>%
    left_join(pops %>%
      filter(level != "age_school") %>%
      select(level, geography_code, population),
      by = c("level", "geography_code")
    ) %>%
    select(level,
      publication_date,
      start_date,
      end_date,
      middle = proportion_pos,
      lower = proportion_pos_low_95,
      upper = proportion_pos_high_95,
      variable = geography_code, region,
      population
    )
  prev_age <- readr::read_csv(here::here("data-processed", "cis_age.csv")) %>%
    left_join(pops %>%
      filter(level == "age_school") %>%
      select(level, lower_age_limit, population),
      by = c("level", "lower_age_limit")
    ) %>%
    mutate(age_group = limits_to_agegroups(lower_age_limit)) %>%
    select(level,
      publication_date,
      start_date,
      end_date,
      middle = proportion_pos,
      lower = proportion_pos_low_95,
      upper = proportion_pos_high_95,
      variable = age_group,
      population
    )
  prev_variants <- readr::read_csv(here::here("data-processed", "cis_variants.csv")) %>%
    left_join(pops %>%
      filter(level != "age_school") %>%
      select(level, geography_code, population),
      by = c("level", "geography_code")
    ) %>%
    select(level,
      publication_date,
      start_date,
      end_date,
      middle = proportion_pos,
      lower = proportion_pos_low_95,
      upper = proportion_pos_high_95,
      geography, variant,
      population
    )
  if (nhse_regions) {
    prev_variants <- prev_variants %>%
      mutate(geography = ons_to_nhse_region(geography)) %>%
      pivot_longer(c(middle, lower, upper)) %>%
      group_by(
        level, publication_date, geography, variant, start_date, end_date, name
      ) %>%
      summarise(
        value = sum(population * value) / sum(population),
        population = sum(population),
        .groups = "drop"
      ) %>%
      pivot_wider()
   }
   prev_variants <- prev_variants %>%
     filter(variant != "virus_too_low_for_variant_to_be_identifiable") %>%
     mutate(variable = paste(variant, geography, sep = "|")) %>%
     select(-variant, -geography)
   prev <- bind_rows(prev_regional, prev_local, prev_age, prev_variants) %>%
    mutate(date = start_date + (end_date - start_date) / 2)

  ## combine as quantile-wise median
  prev <- prev %>%
    pivot_longer(c(lower, middle, upper)) %>%
    group_by(
      level, start_date, end_date, variable,
      region, date, name
    ) %>%
    summarise(
      value = median(value),
      population = median(population),
      .groups = "drop") %>%
    pivot_wider()

  return(prev)
}

read_pop <- function(ab = FALSE) {
  readr::read_csv(here::here(
    "data-processed", paste0("populations", if_else(ab, "_ab", ""), ".csv")
  ))
}

read_ab <- function(nhse_regions = TRUE, threshold = "higher",
                    max_publication_date = NULL) {
  pops <- read_pop(ab = TRUE)
  lower_age_limits <- read_cis() %>%
    filter(level == "age_school") %>%
    select(variable) %>%
    distinct() %>%
    mutate(lower_age_limit = parse_number(sub("-\\+.*$", "", variable))) %>%
    pull(lower_age_limit)
  ab_regional <- readr::read_csv(here::here("data-processed", "ab.csv")) %>%
    filter(threshold_level == threshold) %>%
    left_join(pops %>%
      filter(level != "age_school") %>%
      select(level, geography_code, population),
      by = c("level", "geography_code")
    ) %>%
    select(level,
      publication_date,
      start_date,
      end_date,
      middle = proportion_pos,
      lower = proportion_pos_low_95,
      upper = proportion_pos_high_95,
      variable = geography,
      population
    )

  if (nhse_regions) {
    ab_regional <- ab_regional %>%
      mutate(variable = ons_to_nhse_region(variable)) %>%
      pivot_longer(c(middle, lower, upper)) %>%
      group_by(level, publication_date, start_date, end_date, variable, name) %>%
      summarise(
        value = sum(population * value) / sum(population),
        population = sum(population),
        .groups = "drop"
      ) %>%
      pivot_wider()
  }
  ab_age <- readr::read_csv(here::here("data-processed", "ab_age.csv")) %>%
    left_join(pops %>%
      filter(level == "age_school") %>%
      select(level, lower_age_limit, population),
      by = c("level", "lower_age_limit")
    ) %>%
    mutate(level = "age_school") %>%
    select(level,
      publication_date,
      start_date,
      end_date,
      middle = proportion_pos,
      lower = proportion_pos_low_95,
      upper = proportion_pos_high_95,
      variable = lower_age_limit,
      population
    ) %>%
    mutate(
      variable =
        reduce_agegroups(variable, lower_age_limits)
    ) %>%
    pivot_longer(c(middle, lower, upper)) %>%
    group_by(level, publication_date, start_date, end_date, variable, name) %>%
    summarise(
      value = sum(population * value) / sum(population),
      population = sum(population),
      .groups = "drop"
    ) %>%
    pivot_wider() %>%
    mutate(variable = limits_to_agegroups(variable))
  ab <- bind_rows(ab_regional, ab_age) %>%
    mutate(date = start_date + (end_date - start_date) / 2)
  if (!is.null(max_publication_date)) {
    ab <- ab %>%
      filter(publication_date <= max_publication_date)
  }
  ## combine as quantile-wise median
  ab <- ab %>%
    filter(publication_date == max(publication_date))

  return(ab)
}

read_vacc <- function(nhse_regions = TRUE, max_publication_date = NULL) {
  pops <- read_pop()
  vacc_read <- readr::read_csv(here::here("data-processed", "vacc.csv")) 
  vacc_regional <- vacc_read %>%
    filter(level %in% c("national", "regional")) %>%
    select(-lower_age_limit) %>%
    left_join(pops %>%
      filter(level %in% c("national", "regional")) %>%
      select(level, geography, population),
      by = c("level", "geography")
    ) %>%
    mutate(vaccinated = vaccinated / population) %>%
    select(level,
      date = vaccination_date,
      vaccinated, variable = geography,
      population
    )
  if (nhse_regions) {
    vacc_regional <- vacc_regional %>%
      mutate(variable = ons_to_nhse_region(variable)) %>%
      group_by(level, date, variable) %>%
      summarise(
        vaccinated = sum(population * vaccinated) / sum(population),
        .groups = "drop"
      )
  }
  vacc_local <- vacc_read %>%
    filter(level == "local") %>%
    select(-lower_age_limit) %>%
    left_join(pops %>%
      filter(level == "local") %>%
      select(level, geography = geography_code, population),
      by = c("level", "geography")
    ) %>%
    mutate(vaccinated = vaccinated / population) %>%
    select(level,
      date = vaccination_date,
      vaccinated, variable = geography, region,
      population
    )
   vacc_age <- vacc_read %>%
    filter(level == "age_school") %>%
    left_join(pops %>%
      filter(level == "age_school") %>%
      select(level, lower_age_limit, population),
      by = c("level", "lower_age_limit")
    ) %>%
    mutate(
      vaccinated = vaccinated / population,
      age_group = limits_to_agegroups(lower_age_limit)
    ) %>%
    select(level,
      date = vaccination_date,
      vaccinated, variable = age_group
    )
  vacc <- bind_rows(vacc_regional, vacc_local, vacc_age)
  if (!is.null(max_publication_date)) {
    vacc <- vacc %>%
      filter(date <= max_publication_date)
  }
  return(vacc)
}

read_early <- function(nhse_regions = TRUE) {
  early <- readr::read_csv(here::here("data-processed", "early-seroprevalence.csv"))
  if (nhse_regions) {
    pops <- read_pop()
    early <- early %>%
      left_join(pops %>%
        filter(level != "age_school") %>%
        select(level, variable = geography, population),
        by = c("level", "variable")
      ) %>%
      replace_na(list(population = 1)) %>% ## equal weighting if no info
      mutate(variable = ons_to_nhse_region(variable)) %>%
      pivot_longer(c(mean, lower, upper)) %>%
      group_by(level, variable, name) %>%
      summarise(
        value = sum(population * value) / sum(population),
        .groups = "drop"
      ) %>%
      pivot_wider()
  }
   return(early)
}

read_prob_detectable <- function() {
  data.table::fread("data-processed/prob_detectable.csv")
}
