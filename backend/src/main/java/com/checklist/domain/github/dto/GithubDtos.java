package com.checklist.domain.github.dto;
import com.checklist.domain.checklist.dto.ItemDtos;
import java.util.List;
public final class GithubDtos {
private GithubDtos(){}
 public record Request(String repository,String token,Integer page,String state){}
 public record Issue(int number,String title,String body,String htmlUrl,String state){}
 public record Page(List<Issue> issues,boolean hasNext,int page){}
 public record ImportRequest(String repository,String token,List<Integer> issueNumbers,Long parentId){}
 public record Imported(List<ItemDtos.Item> created,List<Integer> skipped){}
}