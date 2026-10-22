package com.checklist.domain.checklist.service;
import java.time.*;
public final class ItemPeriod {
 private ItemPeriod() {}
 public record Range(LocalDate start,LocalDate endExclusive) {}
 public static Range resolve(String period,LocalDate from,LocalDate to,LocalDate today) {
  LocalDate start,end;
  switch(period==null?"thisMonth":period) {
   case "thisMonth" -> {start=today.withDayOfMonth(1);end=start.plusMonths(1);}
   case "thisWeek" -> {start=today.with(DayOfWeek.MONDAY);end=start.plusWeeks(1);}
   case "lastWeek" -> {end=today.with(DayOfWeek.MONDAY);start=end.minusWeeks(1);}
   case "nextWeek" -> {start=today.with(DayOfWeek.MONDAY).plusWeeks(1);end=start.plusWeeks(1);}
   case "lastYear" -> {end=today.plusDays(1);start=end.minusYears(1);}
   case "custom" -> {
    if(from==null||to==null||to.isBefore(from)||!to.isBefore(from.plusYears(1)))throw new IllegalArgumentException("조회 기간은 시작일부터 최대 1년 이내여야 합니다.");
    start=from;end=to.plusDays(1);
   }
   default -> throw new IllegalArgumentException("지원하지 않는 조회 기간입니다.");
  }
  return new Range(start,end);
 }
}