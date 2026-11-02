// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
fn leap(year : Int32) -> Bool {
  year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

///|
fn digits(
  text : String,
  start : Int32,
  count : Int32,
) -> Int32 raise UsageError {
  let mut value = 0
  for i in start..<(start + count) {
    let c = text[i]
    if c < '0' || c > '9' {
      raise InvalidArguments
    }
    value = value * 10 + c.to_int() - 48
  }
  value
}

///|
// Strict UTC calendar, 0001..9999, no leap seconds or implicit local timezone.
fn parse_at(text : String) -> Int64 raise UsageError {
  if text.length() != 20 && text.length() != 24 {
    raise InvalidArguments
  }
  if text[4] != '-' ||
    text[7] != '-' ||
    text[10] != 'T' ||
    text[13] != ':' ||
    text[16] != ':' ||
    text[text.length() - 1] != 'Z' {
    raise InvalidArguments
  }
  let year = digits(text, 0, 4)
  let month = digits(text, 5, 2)
  let day = digits(text, 8, 2)
  let hour = digits(text, 11, 2)
  let minute = digits(text, 14, 2)
  let second = digits(text, 17, 2)
  let months = [
    31,
    if leap(year) {
      29
    } else {
      28
    },
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31,
  ]
  if year < 1 ||
    month < 1 ||
    month > 12 ||
    hour > 23 ||
    minute > 59 ||
    second > 59 {
    raise InvalidArguments
  }
  if day < 1 || day > months[month - 1] {
    raise InvalidArguments
  }
  let ms = if text.length() == 24 {
    if text[19] != '.' {
      raise InvalidArguments
    }
    digits(text, 20, 3)
  } else {
    0
  }
  let y = year - 1
  let mut days = y * 365 + y / 4 - y / 100 + y / 400 - 719162
  for m in 0..<(month - 1) {
    days += months[m]
  }
  days += day - 1
  ((days.to_int64() * 24L + hour.to_int64()) * 60L + minute.to_int64()) * 60000L +
  second.to_int64() * 1000L +
  ms.to_int64()
}
