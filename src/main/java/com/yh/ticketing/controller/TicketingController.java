package com.yh.ticketing.controller;

import com.yh.ticketing.model.Booking;
import com.yh.ticketing.service.TicketingService;
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
    public ResponseEntity<?> reserve(
            @PathVariable Long ticketId,
            @RequestParam String userId,
            @RequestParam String userName) {
        try {
            Booking booking = redissonLockFacade.reserveWithLock(ticketId, userId, userName);
            return ResponseEntity.status(HttpStatus.CREATED).body(booking);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @GetMapping("/my")
    public ResponseEntity<List<Booking>> getMyBookings(@RequestParam String userId) {
        return ResponseEntity.ok(ticketingService.getMyBookings(userId));
    }
}