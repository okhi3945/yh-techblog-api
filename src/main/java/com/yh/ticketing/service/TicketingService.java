package com.yh.ticketing.service;

import com.yh.ticketing.model.Booking;
import com.yh.ticketing.model.Ticket;
import com.yh.ticketing.repository.BookingRepository;
import com.yh.ticketing.repository.TicketRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.concurrent.TimeUnit;

@Service
@RequiredArgsConstructor
public class TicketingService {
    private final TicketRepository ticketRepository;
    private final BookingRepository bookingRepository;
    private final StringRedisTemplate redisTemplate;

    # Redis 사용 코드
    @Transactional
    public Booking reserve(Long ticketId, String userId, String userName) {
        String lockKey = "lock:ticket:" + ticketId;
        
        // Redis 분산 락 (5초 점유) - 동시성 제어 핵심
        Boolean isLocked = redisTemplate.opsForValue().setIfAbsent(lockKey, "locked", 5, TimeUnit.SECONDS);

        if (Boolean.FALSE.equals(isLocked)) {
            throw new RuntimeException("현재 요청자가 많습니다. 잠시 후 다시 시도해주세요.");
        }

        try {
            Ticket ticket = ticketRepository.findById(ticketId)
                    .orElseThrow(() -> new RuntimeException("티켓 정보가 없습니다."));
            
            ticket.decrease(); // 재고 차감
            
            Booking booking = Booking.builder()
                    .ticketId(ticketId)
                    .userId(userId)
                    .userName(userName)
                    .build();
            
            return bookingRepository.save(booking);
        } finally {
            redisTemplate.delete(lockKey); // 락 해제
        }
    }

    public List<Booking> getMyBookings(String userId) {
        return bookingRepository.findByUserId(userId);
    }
}