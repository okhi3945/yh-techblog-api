package com.yh.ticketing.service;

import com.yh.ticketing.model.Booking;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.redisson.api.RLock;
import org.redisson.api.RedissonClient;
import org.springframework.stereotype.Component;

import java.util.concurrent.TimeUnit;

@Slf4j
@Component
@RequiredArgsConstructor
public class RedissonLockFacade {
    private final RedissonClient redissonClient;
    private final TicketingService ticketingService;

    // Facade : 소프트웨어 설계(디자인 패턴)에서는 복잡한 내부 로직을 감추고, 사용자가 쉽게 쓸 수 있도록 앞에 내새운 간단한 인터페이스
    // 복잡성을 은닉하기 위해 Facade를 생성하여, Ticekting Service 클래스에서 락 기술이 아닌 오직 티켓 예매의 순수한 비즈니스 로직만 가질 수 있게 코드를 분리함

    public Booking reserveWithLock(Long ticketId, String userId, String userName) {
        // 1. 락의 대상(Key) 설정
        RLock lock = redissonClient.getLock("lock:ticket:" + ticketId);

        try {
            // 2. 락 획득 시도 (최대 10초 대기, 락 획득 후 3초간 점유)
            // - waitTime: 다른 사람이 락을 잡고 있다면 최대 10초까지 기다리게 함 (redisson 라이브러리의 대기 기능)
            // - leaseTime: 락을 잡은 후 3초가 지나면 자동으로 풀려 데드락 방지
            boolean available = lock.tryLock(10, 3, TimeUnit.SECONDS);

            if (!available) {
                log.info("락 획득 실패 - ticketId: {}, userId: {}", ticketId, userId);
                throw new RuntimeException("현재 대기자가 너무 많습니다. 다시 시도해주세요.");
            }

            // 3. 비즈니스 로직 실행 (트랜잭션 시작 및 커밋)
            // 이 메서드가 리턴될 때 @Transactional이 종료되며 DB 커밋이 완료
            return ticketingService.reserve(ticketId, userId, userName);

        } catch (InterruptedException e) {
            throw new RuntimeException("서버 오류가 발생했습니다.");
        } finally {
            // 4. 로직이 종료된 후(커밋 완료 후) 반드시 락을 해제
            if (lock.isLocked() && lock.isHeldByCurrentThread()) {
                lock.unlock();
            }
        }
    }
}