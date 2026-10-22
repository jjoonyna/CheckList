package com.checklist.domain.checklist.controller;
import com.checklist.domain.checklist.dto.ItemDtos;
import com.checklist.domain.checklist.service.ItemService;


import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import java.util.*;
@RestController @RequestMapping("/api/items") public class ItemController {
 private final ItemService service;public ItemController(ItemService s){service=s;}
 @GetMapping public List<ItemDtos.Item> list(@AuthenticationPrincipal Long id,@RequestParam(defaultValue="all")String scope,@RequestParam(defaultValue="all")String status,@RequestParam(defaultValue="thisMonth")String period,@RequestParam(required=false)String q,@RequestParam(required=false) @org.springframework.format.annotation.DateTimeFormat(iso=org.springframework.format.annotation.DateTimeFormat.ISO.DATE) java.time.LocalDate from,@RequestParam(required=false) @org.springframework.format.annotation.DateTimeFormat(iso=org.springframework.format.annotation.DateTimeFormat.ISO.DATE) java.time.LocalDate to){return service.list(id,scope,status,period,q,from,to);}
 @PostMapping public ItemDtos.Item create(@AuthenticationPrincipal Long id,@RequestBody ItemDtos.Input in){return service.create(id,in);}
 @PatchMapping("/{id}") public ItemDtos.Item update(@AuthenticationPrincipal Long uid,@PathVariable long id,@RequestBody ItemDtos.Input in){return service.update(uid,id,in);}
 @PatchMapping("/{id}/status") public ItemDtos.Item status(@AuthenticationPrincipal Long uid,@PathVariable long id,@RequestBody ItemDtos.StatusInput in){return service.status(uid,id,in);}
}
