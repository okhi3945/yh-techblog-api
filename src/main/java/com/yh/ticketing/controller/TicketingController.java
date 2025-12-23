package com.yh.ticketing.controller;

import com.yh.ticketing.model.Booking;
import com.yh.ticketing.service.TicketingService;
import com.yh.ticketing.service.RedissonLockFacade;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/v1/tickets")
@RequiredArgsConstructor
public class TicketingController {

    private final TicketingService ticketingService;
    private final RedissonLockFacade redissonLockFacade;

    @PostMapping("/{ticketId}/reserve")
    public Booking reserve(@PathVariable Long ticketId, @RequestParam String userId, @RequestParam String userName) {
        return redissonLockFacade.reserveWithLock(ticketId, userId, userName);
    }

    // 4. 내 예약 확인
    @GetMapping("/my")
    public List<Booking> getMyBookings(@RequestParam String userId) {
        return ticketingService.getMyBookings(userId);
    }
}