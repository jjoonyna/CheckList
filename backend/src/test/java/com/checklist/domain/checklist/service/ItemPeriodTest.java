package com.checklist.domain.checklist.service;
import java.time.LocalDate;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
class ItemPeriodTest {
 @Test void defaultsToCurrentMonthAndUsesMondayWeeks(){
  LocalDate today=LocalDate.of(2026,10,21);
  assertEquals(new ItemPeriod.Range(LocalDate.of(2026,10,1),LocalDate.of(2026,11,1)),ItemPeriod.resolve("thisMonth",null,null,today));
  assertEquals(new ItemPeriod.Range(LocalDate.of(2026,10,19),LocalDate.of(2026,10,26)),ItemPeriod.resolve("thisWeek",null,null,today));
  assertEquals(new ItemPeriod.Range(LocalDate.of(2026,10,12),LocalDate.of(2026,10,19)),ItemPeriod.resolve("lastWeek",null,null,today));
  assertEquals(new ItemPeriod.Range(LocalDate.of(2026,10,26),LocalDate.of(2026,11,2)),ItemPeriod.resolve("nextWeek",null,null,today));
 }
 @Test void permitsExactlyOneCalendarYearIncludingLeapDay(){
  assertEquals(LocalDate.of(2025,1,1),ItemPeriod.resolve("custom",LocalDate.of(2024,1,1),LocalDate.of(2024,12,31),LocalDate.now()).endExclusive());
  assertThrows(IllegalArgumentException.class,()->ItemPeriod.resolve("custom",LocalDate.of(2024,1,1),LocalDate.of(2025,1,1),LocalDate.now()));
 }
 @Test void refusesMissingReversedAndUnboundedRanges(){
  assertThrows(IllegalArgumentException.class,()->ItemPeriod.resolve("custom",null,null,LocalDate.now()));
  assertThrows(IllegalArgumentException.class,()->ItemPeriod.resolve("custom",LocalDate.of(2026,10,22),LocalDate.of(2026,10,21),LocalDate.now()));
  assertThrows(IllegalArgumentException.class,()->ItemPeriod.resolve("all",null,null,LocalDate.now()));
 }
}