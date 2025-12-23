package com.yh.ticketing.repository;
import com.yh.ticketing.model.Ticket;
import org.springframework.data.jpa.repository.JpaRepository;

interface TicketRepository extends JpaRepository<Ticket, Long> {
    List<Ticket> findByPerformanceId(Long performanceId);
}