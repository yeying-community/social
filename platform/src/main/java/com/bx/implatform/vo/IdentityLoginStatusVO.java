package com.bx.implatform.vo;

import lombok.Data;

@Data
public class IdentityLoginStatusVO {
    private String status;
    private String message;
    private LoginVO login;
}
