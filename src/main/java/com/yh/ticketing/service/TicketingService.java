// package com.yh.ticketing.service;

// import com.yh.ticketing.model.Booking;
// import com.yh.ticketing.model.Ticket;
// import com.yh.ticketing.repository.BookingRepository;
// import com.yh.ticketing.repository.TicketRepository;
// import lombok.RequiredArgsConstructor;
// import org.springframework.data.redis.core.StringRedisTemplate;
// import org.springframework.stereotype.Service;
// import org.springframework.transaction.annotation.Transactional;

// import java.util.List;
// import java.util.concurrent.TimeUnit;

// @Service
// @RequiredArgsConstructor
// public class TicketingService {
//     private final TicketRepository ticketRepository;
//     private final BookingRepository bookingRepository;
//     private final StringRedisTemplate redisTemplate; // Redis와 통신하기 위한 도구

//     // 현업에서는 setIfAbsent 방식이 아닌 사용자가 락을 얻을 때까지 잠시 대기하는 Redisson 라이브러리를 선호함
//     // 이 라이브러리를 나중에 사용해봐야겠음
//     @Transactional
//     public Booking reserve(Long ticketId, String userId, String userName) {
//         // 락을 위한 고유 키 생성 (예 : lock:ticket:101)등으로 Key를 생성함
//         String lockKey = "lock:ticket:" + ticketId;
        
//         // Redis의 setIfAbsent를 이용한 분산 락 획득 시도(SETNX 방식)
//         // -> 위에서 정의한 Key가 없을 때만 저장 (성공하면 True, 실패 시 False)
//         // -> 매개변수 (5, TimeUnit.SECONDS); => 5초 후 자동 삭제 생성 (서버가 다운되도 5초 뒤에 풀림)
//         Boolean isLocked = redisTemplate.opsForValue().setIfAbsent(lockKey, "locked", 5, TimeUnit.SECONDS);

//         // 락 획득 실패 시에는 예외를 발생시켜서 동시 접근을 차단함 (isLocked가 FALSE 일 경우)
//         // SETNX(Set if Not Exitst) => 성공 (True) : Redis에 해당 키가 없을 때만 데이터를 씀 (락 획득 성공)
//         // 실패 (False) : Redis에 이미 해당 키가 존재하면 아무것도 하지 않고 False 반환 (락 획득 실패)
//         if (Boolean.FALSE.equals(isLocked)) {
//             throw new RuntimeException("현재 요청자가 많습니다. 잠시 후 다시 시도해주세요.");
//         }

//         try {
//             // 비즈니스 로직, 티켓 ID를 통해 findById로 티켓 존재 여부 확인함
//             Ticket ticket = ticketRepository.findById(ticketId)
//                     .orElseThrow(() -> new RuntimeException("티켓 정보가 없습니다."));
            
//             // 재고를 차감해주는 데 여기서 동시성 이슈가 가장 많이 발생할 것임
//             ticket.decrease(); // 재고 차감
            
//             // 예약 내역을 DB에 저장함 티켓 예매를 하면 바로 예약 테이블로 정보를 생성함
//             Booking booking = Booking.builder()
//                     .ticketId(ticketId)
//                     .userId(userId)
//                     .userName(userName)
//                     .build();
            
//             return bookingRepository.save(booking);
//         } finally {
//             // 로직이 끝날 때 락을 해제하여 다른 사용자가 진입할 수 있게 해줌
//             redisTemplate.delete(lockKey); // 락 해제
//         }
//     }

//     public List<Booking> getMyBookings(String userId) {
//         return bookingRepository.findByUserId(userId);
//     }
// }
package com.yh.ticketing.service;

import com.yh.ticketing.model.Booking;
import com.yh.ticketing.model.Ticket;
import com.yh.ticketing.repository.BookingRepository;
import com.yh.ticketing.repository.TicketRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.List;

@Service
@RequiredArgsConstructor
public class TicketingService {
    private final TicketRepository ticketRepository;
    private final BookingRepository bookingRepository;

    // 부모 클래스(Facade)에서 시작된 트랜잭션이 있다면 참여하고, 없다면 새로 시작시킴
    @Transactional
    public Booking reserve(Long ticketId, String userId, String userName) {
        Ticket ticket = ticketRepository.findById(ticketId)
                .orElseThrow(() -> new RuntimeException("티켓 정보가 없습니다."));
        
        ticket.decrease(); // 재고 차감 재고가 없으면 여기서 RuntimeException 발생함
        
        Booking booking = Booking.builder()
                .ticketId(ticketId)
                .userId(userId)
                .userName(userName)
                .build();
        
        return bookingRepository.save(booking);
    }
    @Transactional(readOnly = true)
    public List<Booking> getMyBookings(String userId) {
        return bookingRepository.findByUserId(userId);
    }
}