package com.yh.ticketing.controller;

import com.yh.ticketing.model.*;
import com.yh.ticketing.service.TicketingService;
import com.yh.ticketing.service.RedissonLockFacade;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
@RestController
@RequestMapping("/api/v1/admin")
@RequiredArgsConstructor
class AdminController {
    private final TicketingService ticketingService;

    // 1. 공연 생성
    @PostMapping("/performance")
    public Performance createPerformance(@RequestBody Performance request) {
        return ticketingService.createPerformance(request.getTitle(), request.getDescription(), request.getStartAt());
    }

    // 2. 공연 ID에 따른 티켓(좌석) 일괄 생성
    @PostMapping("/performance/{performanceId}/tickets")
    public String initTickets(@PathVariable Long performanceId, @RequestParam int count) {
        ticketingService.initTickets(performanceId, count);
        return performanceId + "번 공연에 " + count + "개의 티켓이 생성되었습니다.";
    }
}