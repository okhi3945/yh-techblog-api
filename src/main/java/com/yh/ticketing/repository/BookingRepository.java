package com.yh.ticketing.repository;
import com.yh.ticketing.model.Booking;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface BookingRepository extends JpaRepository<Booking, String> {
    List<Booking> findByUserId(String userId);
}