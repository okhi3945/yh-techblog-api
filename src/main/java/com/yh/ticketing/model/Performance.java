package com.yh.ticketing.model;

import jakarta.persistence.*;
import lombok.*;
import org.redisson.api.RLock;
import org.redisson.api.RedissonClient;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.TimeUnit;
@Entity
@Table(name = "performances")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
class Performance {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    private String title;          // 공연 제목
    private String description;    // 공연 설명
    private LocalDateTime startAt; // 시작 시간
}