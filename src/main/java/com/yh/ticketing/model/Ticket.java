package com.yh.ticketing.model;

import jakarta.persistence.*;
import lombok.*;

@Entity
@Table(name = "tickets")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
class Ticket {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    
    private Long performanceId;    // 어느 공연의 티켓인가
    private String seatNumber;     // 좌석 번호 (예: A1, A2)

    @Enumerated(EnumType.STRING)
    private TicketStatus status;   // AVAILABLE, BOOKED

    public void reserve() {
        if (this.status != TicketStatus.AVAILABLE) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "이미 예약된 좌석입니다.");
        }
        this.status = TicketStatus.BOOKED;
    }
}

enum TicketStatus { AVAILABLE, BOOKED }