package com.elgris.usersapi.api;

import com.elgris.usersapi.models.User;
import com.elgris.usersapi.repository.UserRepository;
import io.jsonwebtoken.Claims;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;

@RestController()
public class UsersController {

    @Autowired
    private UserRepository userRepository;

    @RequestMapping(value = "/health", method = RequestMethod.GET)
    public Map<String, Object> health() {
        Map<String, Object> response = new HashMap<>();
        response.put("status", "OK");
        response.put("service", "users-api");
        response.put("timestamp", LocalDateTime.now().toString());
        return response;
    }

    @RequestMapping(value = "/users", method = RequestMethod.GET)
    public List<User> getUsers() {
        List<User> response = new LinkedList<>();
        userRepository.findAll().forEach(response::add);

        return response;
    }

    @RequestMapping(value = "/users/{username}", method = RequestMethod.GET)
    public User getUser(HttpServletRequest request, @PathVariable("username") String username) {

        Object requestAttribute = request.getAttribute("claims");
        if ((requestAttribute == null) || !(requestAttribute instanceof Claims)) {
            throw new RuntimeException("Did not receive required data from JWT token");
        }

        Claims claims = (Claims) requestAttribute;

        if (!username.equalsIgnoreCase((String) claims.get("username"))) {
            throw new AccessDeniedException("No access for requested entity");
        }

        return userRepository.findOneByUsername(username);
    }

}
