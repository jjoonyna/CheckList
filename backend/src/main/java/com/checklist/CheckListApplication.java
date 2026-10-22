package com.checklist;



import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication(exclude=org.springframework.boot.autoconfigure.security.servlet.UserDetailsServiceAutoConfiguration.class)
public class CheckListApplication {
    public static void main(String[] args) throws Exception {
        if(args.length==2 && "--checklist-create-database".equals(args[0])){com.checklist.global.setup.DatabaseProvisioner.createIfMissing(java.nio.file.Path.of(args[1]));return;}
        SpringApplication.run(CheckListApplication.class, args);
    }
}
