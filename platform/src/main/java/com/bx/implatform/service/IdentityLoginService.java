package com.bx.implatform.service;

import com.bx.implatform.vo.LoginVO;
import com.bx.implatform.vo.IdentityLoginSessionVO;
import com.bx.implatform.vo.IdentityLoginStatusVO;

import java.util.Map;

public interface IdentityLoginService {
    IdentityLoginSessionVO createSession();
    IdentityLoginStatusVO getStatus(String sessionId);
    void acceptCallback(String code, String state);
    LoginVO verifyWalletPresentation(Map<String, Object> request);
}
