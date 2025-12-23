package com.yh.ticketing.repository;
import com.yh.ticketing.model.Performance;
import org.springframework.data.jpa.repository.JpaRepository;

interface PerformanceRepository extends JpaRepository<Performance, Long> {}