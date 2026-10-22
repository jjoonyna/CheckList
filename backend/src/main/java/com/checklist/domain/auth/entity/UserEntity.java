package com.checklist.domain.auth.entity;



import jakarta.persistence.*;

@Entity @Table(name="app_user")
public class UserEntity {
    @Id @GeneratedValue(strategy=GenerationType.IDENTITY) public Long id;
    @Column(nullable=false, unique=true, length=320) public String email;
    @Column(name="password_hash", nullable=false, length=100) public String passwordHash;
    @Column(nullable=false, length=100) public String name;
    public Long getId() { return id; }
    public String getEmail() { return email; }
    public String getName() { return name; }
    public String getPasswordHash() { return passwordHash; }
    protected UserEntity() {}
    public UserEntity(String email, String passwordHash, String name) { this.email=email; this.passwordHash=passwordHash; this.name=name; }
}
